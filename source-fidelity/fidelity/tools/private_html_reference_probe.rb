# frozen_string_literal: true
# The SINGLE authorized original Rails HTML actor. No raw response, cookie,
# setting value, SQL bind or production row is written to retained evidence.
require "json"
require "digest"
require "fileutils"
root_directory = File.expand_path("../..", __dir__)
usage_path = File.join(root_directory, "run/PRIVATE_PG_HTML_USAGE_20261107.json")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
loop do
  usage = File.open(usage_path) do |file|
    file.flock(File::LOCK_SH)
    JSON.parse(file.read)
  end
  break if usage["phase"] == "rails_running" && usage["rails_pid"] == Process.pid
  raise "private HTML actor gate timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  sleep 0.01
end
require_relative "oracle_isolation"
require "rack/mock"
at_exit { FidelityOracleIsolation.cleanup_vips! }
output = ENV.fetch("FIDELITY_PRIVATE_HTML_OUTPUT")
FileUtils.mkdir_p(output)
source_root = File.realpath(".") + "/"
callbacks = []
trace = TracePoint.new(:call, :return, :script_compiled) do |event|
  if event.event == :script_compiled
    file = event.instruction_sequence&.path
    raise "private HTML compiled a plugin" if file && File.expand_path(file).start_with?(source_root + "plugins/")
    next
  end
  path = event.path.delete_prefix(source_root)
  methods = {
    "lib/wizard.rb" => [:requires_completion?],
    "lib/site_settings/db_provider.rb" => [:save],
    "lib/site_setting_extension.rb" => [:add_override!, :notify_changed!],
    "app/models/stylesheet_cache.rb" => [:add],
    "lib/application_layout_preloader.rb" => [:preloaded_data, :preload_anonymous_data],
    "app/serializers/site_serializer.rb" => [:include_wizard_required?],
    "lib/topic_list_responder.rb" => [:respond_with_list],
  }
  if methods.fetch(path, []).include?(event.method_id)
    callbacks << {phase: event.event, source: path, line: event.lineno, method: event.method_id}
  end
end

def typed(value)
  case value
  when Hash then value.sort.to_h.transform_values { |item| typed(item) }
  when Array then value.map { |item| typed(item) }
  else [value.class.name, value]
  end
end

def shape(value, depth = 0)
  return value.class.name if depth >= 4
  case value
  when Hash then value.transform_values { |item| shape(item, depth + 1) }
  when Array then {"array_count" => value.size, "element_shapes" => value.map { |item| shape(item, depth + 1) }.uniq}
  else value.class.name
  end
end

begin
  trace.enable
  raise "private original core policy" unless ENV.fetch("LOAD_PLUGINS") == "0"
  require File.expand_path("config/environment.rb")
  raise "private original loaded plugins" if GlobalSetting.load_plugins? || !Discourse.plugins.empty?
  connection = ActiveRecord::Base.connection
  FidelityOracleIsolation.verify_pg_connection!(connection.raw_connection, constructor: "original_html_ready")
  # Real source datum is inspected, never changed by the test driver.
  before = {stylesheet_rows: StylesheetCache.count, bypass_wizard_check: SiteSetting.bypass_wizard_check?}
  rows = []
  ["/latest", "/latest?page=1"].each do |path|
    uri = URI.parse(Discourse.base_url + path)
    host = uri.host + (uri.default_port == uri.port ? "" : ":#{uri.port}")
    env = {"HTTP_HOST" => host, "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"}
    html_response = Rack::MockRequest.new(Rails.application).get(uri.to_s, env.merge("HTTP_ACCEPT" => "text/html"))
    doc = Nokogiri::HTML5(html_response.body)
    if html_response.status != 200
      # Only error class/source stack survives. No Rails diagnostic HTML/SQL.
      error = doc.at_css("h1")&.text.to_s.strip
      locations = doc.text.scan(/(?:app|lib)\/[a-zA-Z0-9_\/.-]+\.rb:\d+/).uniq
      File.write(File.join(output, "html-failure.json"), JSON.pretty_generate({status: html_response.status,
        error_heading_sha256: Digest::SHA256.hexdigest(error), original_source_locations: locations}) + "\n")
      raise "original private HTML returned #{html_response.status}"
    end
    preload_node = doc.at_css("#data-preloaded")
    raise "original HTML lacks real preloads" unless preload_node
    preloads = JSON.parse(preload_node.text)
    parsed = preloads.transform_values { |value| value.is_a?(String) ? JSON.parse(value) : value }
    topic_list = parsed.fetch("topic_list")
    raise "missing actual site/settings preloads" unless parsed.fetch("site").is_a?(Hash) && parsed.fetch("siteSettings").is_a?(Hash)
    json_uri = uri.dup
    json_uri.path = "/latest.json"
    json_response = Rack::MockRequest.new(Rails.application).get(json_uri.to_s, env.merge("HTTP_ACCEPT" => "application/json"))
    raise "paired original JSON failed" unless json_response.status == 200
    payload = JSON.parse(json_response.body)
    raise "HTML topic preload differs from JSON values/types" unless typed(topic_list) == typed(payload)
    topics = topic_list.fetch("topic_list").fetch("topics")
    raise "default HTML has no topics" if path == "/latest" && topics.empty?
    scripts = doc.css("script[src]").map { |node| URI.parse(node["src"]).path }
    styles = doc.css('link[rel="stylesheet"]').map { |node| URI.parse(node["href"]).path }
    modules = doc.css('link[rel="modulepreload"]').map { |node| URI.parse(node["href"]).path }
    raise "HTML lacks genuine scripts/styles/module preloads" if scripts.empty? || styles.empty? || modules.empty?
    row = {path: path, html_status: html_response.status, json_status: json_response.status,
      html_bytes: html_response.body.bytesize, html_sha256: Digest::SHA256.hexdigest(html_response.body),
      topic_count: topics.size, topic_payload_sha256: Digest::SHA256.hexdigest(JSON.generate(typed(payload))),
      complete_topic_values_and_types_equal: true, preload_shapes: parsed.transform_values { |value| shape(value) },
      script_paths: scripts, stylesheet_paths: styles, module_preload_paths: modules,
      element_counts: doc.css("*").group_by(&:name).transform_values(&:size)}
    rows << row
    File.write(File.join(output, "html-reference.json"), JSON.pretty_generate({requests: rows,
      native_html_executed: false, browser_rendered: false, page_accepted: false}) + "\n")
  end
  after = {stylesheet_rows: StylesheetCache.count, bypass_wizard_check: SiteSetting.bypass_wizard_check?}
  raise "original wizard effect not executed" unless before[:bypass_wizard_check] == false && after[:bypass_wizard_check] == true
  raise "original CSS effect not executed" unless after[:stylesheet_rows] > before[:stylesheet_rows]
  File.write(File.join(output, "original-effects.json"), JSON.pretty_generate({
    css_rows_added: after[:stylesheet_rows] - before[:stylesheet_rows], wizard_false_to_true: true,
    callback_events: callbacks, original_callbacks_replaced: false, forced_settings: false,
    native_html_executed: false, browser_rendered: false, page_accepted: false}) + "\n")
rescue Exception => error
  File.write(File.join(output, "reference-error.json"), JSON.pretty_generate({error_class: error.class.name,
    message_sha256: Digest::SHA256.hexdigest(error.message),
    source_frames: error.backtrace.to_a.filter_map { |frame| frame[/\A#{Regexp.escape(source_root)}((?:app|lib)\/[^:]+\.rb:\d+)/, 1] },
    callback_events: callbacks, native_html_executed: false, page_accepted: false}) + "\n")
  raise
ensure
  trace.disable
end
