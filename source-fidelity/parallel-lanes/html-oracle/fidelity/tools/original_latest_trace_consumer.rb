# frozen_string_literal: true
# Original Rails runtime trace consumer. Observation-only: it never replaces an
# application method/getter, never serializes raw response values, and blocks
# external job/message dispatch before the original method body can run.
require "json"
require "pathname"
require "rack/mock"
require_relative "oracle_observation"

root = File.expand_path(ENV.fetch("FIDELITY_DISCOURSE_ROOT"))
out = File.expand_path(ENV.fetch("FIDELITY_TRACE_OUTPUT"))
guard = File.expand_path(ENV.fetch("FIDELITY_ORACLE_GUARD"))
require guard
at_exit { FidelityOracleIsolation.cleanup_vips! }

module OriginalLatestTrace
  ROOT = File.expand_path(ENV.fetch("FIDELITY_DISCOURSE_ROOT")).freeze
  OUTPUT = File.expand_path(ENV.fetch("FIDELITY_TRACE_OUTPUT")).freeze
  TRACE_PATHS = %r{\A(?:app/(?:controllers/(?:application_controller|list_controller)|helpers/application_helper|models/(?:site_setting|theme_site_setting|topic_list|topic|category)|serializers/(?:topic_list|topic_list_item))\.rb|lib/(?:site_setting_extension|site_settings/(?:yaml_loader|defaults_provider|db_provider|type_supervisor)|discourse_plugin_registry|plugin(?:/instance|/metadata|/js_manager)?|upcoming_changes|application_layout_preloader|topic_list_responder|topic_query_params|topic_query|ember_assets|stylesheet(?:/[^/]+)*|system_themes_manager)\.rb|app/models/remote_theme\.rb)\z}
  PRELOADER_REQUIREMENTS = [
    ["lib/application_layout_preloader.rb", "preloaded_data"],
    ["lib/application_layout_preloader.rb", "preload_anonymous_data"],
    ["lib/application_layout_preloader.rb", "preload_upcoming_change_data"],
    ["lib/application_layout_preloader.rb", "activated_themes_json"],
    ["lib/site_setting_extension.rb", "client_settings_json"],
    ["lib/site_setting_extension.rb", "theme_site_settings_json"],
    ["lib/upcoming_changes.rb", "enabled_for_user?"],
    ["app/models/theme_site_setting.rb", "generate_theme_map"]
  ].freeze
  SOURCE_LINE_WATCH = {
    "app/models/site_setting.rb" => [109, 119, 126, 131, 140],
    "lib/site_setting_extension.rb" => [243, 246, 1066, 1084, 1143, 1318, 1438],
    "lib/site_settings/yaml_loader.rb" => [8, 9, 10, 11, 18, 20, 23],
    "config/initializers/005-site_settings.rb" => [18, 19, 22]
  }.freeze

  class ForbiddenExternalEffect < SecurityError; end

  @phase = "bootstrap"
  @sequence = 0
  @methods = {}
  @anonymous_methods = {}
  @errors = []
  @external_attempts = []
  @exceptions = []
  @source_lines = {}

  class << self
    attr_reader :phase

    def phase=(value)
      @phase = value
      FidelityOracleObservation.set_phase(value)
      ENV["FIDELITY_ORACLE_PHASE"] = value
    end

    def relative(path)
      Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(ROOT)).to_s
    rescue ArgumentError
      nil
    end

    def external_dispatch?(owner, method)
      # MessageBus only dispatches to this run's owned Valkey fixture. Its Redis
      # client is independently endpoint-guarded and every PUBLISH is recorded;
      # this is not an external message/service. Jobs remain forbidden.
      return false if method == "publish" && owner.to_s.include?("MessageBus")
      return false unless %w[perform_later enqueue push broadcast deliver_later].include?(method.to_s)
      owner.to_s.match?(/ActiveJob|Sidekiq|MessageBus|ActionCable|Jobs::|Discourse::Jobs/)
    end

    def trace(event)
      context = FidelityOracleObservation.context
      if event.event == :line
        raw_path = event.path.to_s
        prefix = ROOT.end_with?("/") ? ROOT : "#{ROOT}/"
        return unless raw_path.start_with?(prefix)
        path = raw_path.delete_prefix(prefix)
        return unless SOURCE_LINE_WATCH.fetch(path, []).include?(event.lineno)
        @sequence += 1
        owner = event.defined_class.to_s
        method = event.method_id.to_s
        key = [context[:phase], context[:thread_id], path, event.lineno, owner, method]
        row = (@source_lines[key] ||= { **context, phase: context[:phase], source: path, line: event.lineno,
                                        owner: owner, method: method, hits: 0, first_order: @sequence })
        row[:hits] += 1
        return
      end
      if event.event == :raise
        if (context[:phase].to_s.start_with?("request_") || context[:thread_role] == "concurrent") && @exceptions.length < 200
          error = event.raised_exception
          stack = Array(error.backtrace_locations).filter_map do |frame|
            source = relative(frame.absolute_path || frame.path)
            { source: source, line: frame.lineno, method: frame.base_label } if source
          end.first(12)
          signature = [context[:phase], context[:thread_id], error.class.name, stack.first(5)]
          unless @exception_signatures&.include?(signature)
            @exception_signatures ||= []
            @exception_signatures << signature
            @exceptions << { **context, phase: context[:phase], error_class: error.class.name,
                             source: relative(event.path) || "outside-original-root", line: event.lineno,
                             owner: event.defined_class.to_s, method: event.method_id.to_s, frames: stack }
          end
        end
        return
      end
      return unless event.event == :call
      owner = event.defined_class.to_s
      method = event.method_id.to_s
      if external_dispatch?(owner, method)
        path = relative(event.path)
        @external_attempts << { **context, phase: context[:phase], owner: owner, method: method,
                                 source: path, line: event.lineno }
        raise ForbiddenExternalEffect, "external dispatch blocked before method body"
      end
      raw_path = event.path.to_s
      prefix = ROOT.end_with?("/") ? ROOT : "#{ROOT}/"
      return unless raw_path.start_with?(prefix)
      path = raw_path.delete_prefix(prefix)
      return unless TRACE_PATHS.match?(path) || path.start_with?("plugins/")

      site_setting = Object.const_defined?(:SiteSetting, false) && event.self.equal?(Object.const_get(:SiteSetting, false))
      @sequence += 1
      key = [context[:phase], context[:thread_id], context[:request_id], context[:active_request_id],
             path, event.lineno, owner, method, site_setting]
      row = (@methods[key] ||= { **context, phase: context[:phase], source: path, line: event.lineno,
                                  owner: owner,
                                  method: method, site_setting_receiver: site_setting,
                                  calls: 0, first_order: @sequence })
      row[:calls] += 1
      if path.start_with?("plugins/") || method.match?(/modifier|preload|callback|register/)
        row[:hook_candidate] = true
      end
      if site_setting
        getter = (@anonymous_methods[key] ||= row.dup)
        getter[:calls] = row[:calls]
      end
    end

    def request(path, accept)
      @request_sequence = @request_sequence.to_i + 1
      request_id = "request-#{@request_sequence}"
      phase = @phase
      request_context = FidelityOracleObservation.begin_request(phase: phase, request_id: request_id, path: path)
      env = nil
      begin
        wrapped_app = lambda do |request_env|
          env = request_env
          Rails.application.call(request_env)
        end
        response = Rack::MockRequest.new(wrapped_app).get(
          path, "HTTP_HOST" => "localhost", "HTTP_ACCEPT" => accept,
          "REMOTE_ADDR" => "127.0.0.1", "rack.url_scheme" => "http",
        )
        info = { status: response.status, content_type: response["content-type"],
                 body_bytes: response.body.bytesize, request_context: request_context }
        request_exceptions = %w[action_dispatch.exception action_dispatch.original_exception].filter_map do |key|
          exception = env[key]
          summary = FidelityOracleObservation.safe_exception(exception, root: ROOT)
          { environment_key: key, **summary } if summary
        end.uniq
        info[:request_exceptions] = request_exceptions unless request_exceptions.empty?
        if accept.include?("application/json") && response.status < 500
          begin
            payload = JSON.parse(response.body)
            info[:json_keys] = payload.is_a?(Hash) ? payload.keys.map(&:to_s).sort : []
            topic_list = payload.is_a?(Hash) ? (payload["topic_list"] || payload["topicList"]) : nil
            if topic_list.is_a?(Hash)
              topics = topic_list["topics"] || topic_list["topic_list"] || []
              info[:topic_count] = topics.length if topics.respond_to?(:length)
              first = topics.first if topics.respond_to?(:first)
              info[:first_topic_keys] = first.keys.map(&:to_s).sort if first.is_a?(Hash)
              info[:topic_list_keys] = topic_list.keys.map(&:to_s).sort
            end
          rescue JSON::ParserError
            info[:json_parse] = "not_json"
          end
        end
        info
      rescue Exception => error # rubocop:disable Lint/RescueException -- capture only safe identity/frames
        { error_class: error.class.name, request_context: request_context,
          request_exception: FidelityOracleObservation.safe_exception(error, root: ROOT) }
      ensure
        FidelityOracleObservation.end_request(request_id)
      end
    end

    def source_method(method)
      method.source_location&.then { |path, line| { source: relative(path) || "outside-original-root", line: line } }
    end

    def effects_for(phase)
      file = ENV.fetch("FIDELITY_VALKEY_WRITE_LOG")
      return [] unless File.file?(file)
      File.readlines(file, chomp: true).filter_map do |line|
        row = JSON.parse(line)
        next unless row["phase"] == phase && row["stage"] == "successful_reply"
        owners = Array(row["caller"]).filter_map do |frame|
          match = frame.match(%r{#{Regexp.escape(ROOT)}/([^:]+):(\d+)})
          { source: match[1], line: match[2].to_i } if match
        end.uniq
        { command: row["command"], key: row["key"], keys: row["keys"], owners: owners }
      end
    end

    def concurrent_effect_summary(request_id)
      file = ENV.fetch("FIDELITY_VALKEY_WRITE_LOG")
      return { record_count: 0, commands: {}, original_callers: [] } unless request_id && File.file?(file)
      rows = File.readlines(file, chomp: true).filter_map do |line|
        row = JSON.parse(line)
        row if row["stage"] == "successful_reply" && row["thread_role"] == "concurrent" &&
               row["active_request_id"] == request_id
      end
      commands = rows.map { |row| row["command"] }.tally
      callers = rows.flat_map do |row|
        Array(row["caller"]).filter_map do |frame|
          match = frame.match(%r{#{Regexp.escape(ROOT)}/([^:]+):(\d+)})
          { source: match[1], line: match[2].to_i } if match
        end
      end.uniq
      { record_count: rows.length, commands: commands, original_callers: callers }
    end

    def phase_result(name, result)
      request_id = result.dig(:request_context, :request_id)
      { name: name, result: result, effects: effects_for(name),
        concurrent_effects: concurrent_effect_summary(request_id) }
    end

    def evidence
      settings = if Object.const_defined?(:SiteSetting, false)
        { setting_getter_source: source_method(SiteSetting.method(:suppress_secured_categories_from_admin)) }
      else
        {}
      end
      plugins = if Object.const_defined?(:Discourse, false) && Discourse.respond_to?(:plugins)
        Discourse.plugins.map(&:name)
      else
        []
      end
      { status: "observed", phases: @phases, settings: settings, original_plugin_names: plugins,
        methods: @methods.values.sort_by { |row| row[:first_order] },
        source_line_events: @source_lines.values.sort_by { |row| row[:first_order] },
        site_setting_calls: @anonymous_methods.values.sort_by { |row| row[:first_order] },
        raised_exceptions: @exceptions,
        external_dispatch_attempts: @external_attempts, method_observation_errors: @errors,
        preloader_source_requirements: PRELOADER_REQUIREMENTS.map do |path, method|
          { source: path, method: method,
            observed: @methods.values.any? { |row| row[:source] == path && row[:method] == method } }
        end }
    end

    def phases=(value)
      @phases = value
    end
  end
end

# Require the original Rails application only after the endpoint guards and
# trace observer are active. TracePoint records method identity/source/order,
# never arguments, return values, cookies, or response bodies.
trace = TracePoint.new(:call, :line, :raise) { |event| OriginalLatestTrace.trace(event) }
OriginalLatestTrace.phase = "boot"
trace.enable
begin
  require File.join(root, "config/environment")
  OriginalLatestTrace.phase = "boot"
  boot_summary = { rails_version: Rails.version,
                   loaded_settings: SiteSetting.defaults.all.keys.length,
                   plugins: Discourse.plugins.map(&:name) }
  boot_summary[:effects] = OriginalLatestTrace.effects_for("boot")

  OriginalLatestTrace.phase = "request_page0"
  page0 = OriginalLatestTrace.request("/latest.json?page=0", "application/json")
  page0_phase = OriginalLatestTrace.phase_result("request_page0", page0)

  OriginalLatestTrace.phase = "request_page1"
  page1 = OriginalLatestTrace.request("/latest.json?page=1", "application/json")
  page1_phase = OriginalLatestTrace.phase_result("request_page1", page1)

  OriginalLatestTrace.phase = "request_html"
  html = OriginalLatestTrace.request("/latest", "text/html")
  html_phase = OriginalLatestTrace.phase_result("request_html", html)

  OriginalLatestTrace.phase = "deliberate_cold_getter"
  containers = SiteSetting.instance_variable_get(:@containers)
  raise "original settings container unavailable" unless containers.is_a?(Hash)
  containers.delete(SiteSetting.provider.current_site)
  getter_value = SiteSetting.suppress_secured_categories_from_admin
  # Do not serialize even the boolean value: only record that the actual getter returned.
  cold = { returned: !getter_value.nil?, source: OriginalLatestTrace.source_method(SiteSetting.method(:suppress_secured_categories_from_admin)),
           effects: OriginalLatestTrace.effects_for("deliberate_cold_getter") }

  OriginalLatestTrace.phases = [
    { name: "boot", result: boot_summary }, page0_phase, page1_phase, html_phase,
    { name: "deliberate_cold_getter", result: cold, effects: cold[:effects] }
  ]
  evidence = OriginalLatestTrace.evidence
  evidence[:stage] = "actual unchanged Rails anonymous request trace; not native acceptance"
  evidence[:anonymous_request_transport] = { cookie_header_sent: false, authorization_header_sent: false,
                                              session_credentials_recorded: false }
  evidence[:preloader_observation] = "HTML page request attempted with original controller/layout; no asset substitution"
  evidence[:page_json_statuses] = { page0: page0[:status], page1: page1[:status] }
  evidence[:failures] = [page0, page1].select { |r| r[:error_class] || (r[:status] && r[:status] >= 500) }
  File.write(File.join(out, "trace.json"), JSON.pretty_generate(evidence) + "\n")
  puts "FIDELITY_ORIGINAL_LATEST_TRACE " + JSON.generate({ status: evidence[:status], phases: evidence[:phases].map { |p| p[:name] },
       page0_status: page0[:status], page1_status: page1[:status], html_status: html[:status],
       method_events: evidence[:methods].length, setting_calls: evidence[:site_setting_calls].length,
       failure_count: evidence[:failures].length })
  exit(evidence[:failures].empty? ? 0 : 2)
 rescue SystemExit
   raise
 rescue Exception => error # rubocop:disable Lint/RescueException -- write non-sensitive failure class and phase
   frames = Array(error.backtrace_locations).first(24).map do |frame|
     { source: frame.absolute_path || frame.path, line: frame.lineno, method: frame.base_label }
   end
   File.write(File.join(out, "trace-error.json"), JSON.pretty_generate({ phase: ENV["FIDELITY_ORACLE_PHASE"],
        error_class: error.class.name, frames: frames,
        external_dispatch_attempts: OriginalLatestTrace.evidence[:external_dispatch_attempts] }) + "\n")
  warn "TRACE_FAILED phase=#{OriginalLatestTrace.phase} error_class=#{error.class.name}"
  exit 1
ensure
  trace.disable
end
