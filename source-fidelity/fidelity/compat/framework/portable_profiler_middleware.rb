# frozen_string_literal: true
require_relative "rack_mini_profiler_core"

module Rack
  class MiniProfiler
    # The normal JSON slice of gem5 MiniProfiler#call, around the framework's
    # real Rack-shaped in-process response. All Page/SQL/store/cookie/header
    # algorithms are original source-derived methods in the adjacent core.
    # Unsupported debug, proxy, cookie and HTML branches REFUSE before the app;
    # they are not silently disabled or counted as request/page acceptance.
    def initialize(app, options = nil)
      raise ArgumentError, "unsupported profiler constructor options" unless options.nil?
      @app = app
      @config = MiniProfiler.config
      @storage = @config.storage_instance
      raise ArgumentError, "profiler storage was not configured" if @storage.nil?
    end

    def validate_core_profile!(env)
      raise ArgumentError, "unsupported profiler request method/path" unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/latest.json"
      validate_direct_context!(env)
    end

    # Shared context validation, not admission to another response profile.
    def validate_direct_context!(env)
      cookie = env["HTTP_COOKIE"]
      raise ArgumentError, "unsupported incoming profiler cookie profile" unless cookie.nil? || cookie == ""
      env.each do |key, _value|
        raise ArgumentError, "unsupported profiler proxy context" if key.start_with?("HTTP_X_FORWARDED") || key == "HTTP_FORWARDED"
      end
      if env["QUERY_STRING"].to_s.include?(@config.profile_parameter + "=") || !env["HTTP_X_RACK_MINI_PROFILER"].to_s.empty?
        raise ArgumentError, "unsupported profiler debug action"
      end
      raise ArgumentError, "unsupported profiler authorization/enabled profile" unless @config.authorization_mode == :allow_all && @config.enabled
      raise ArgumentError, "unsupported profiler snapshot profile" unless @config.snapshot_every_n_requests == 0 && !MiniProfiler.snapshots_transporter?
      raise ArgumentError, "unsupported skipped profiler path" if @config.skip_paths && @config.skip_paths.any? { |pattern| pattern.is_a?(String) ? env["PATH_INFO"].start_with?(pattern) : pattern.match?(env["PATH_INFO"]) }
      raise ArgumentError, "unsupported profiler preauthorization profile" if @config.pre_authorize_cb && !@config.pre_authorize_cb.call(env)
      true
    end

    def call_core(env)
      validate_core_profile!(env)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client_settings = ClientSettings.new(env, @storage, start)
      client_settings.disable_profiling = false
      MiniProfiler.create_current(env, @config)
      if config.disable_caching
        env["HTTP_IF_MODIFIED_SINCE"] = ""
        env["HTTP_IF_NONE_MATCH"] = ""
      end
      original_encoding = env["HTTP_ACCEPT_ENCODING"]
      begin
        env["HTTP_ACCEPT_ENCODING"] = "identity" if config.suppress_encoding
        status, headers, body = @app.call(env)
      ensure
        env["HTTP_ACCEPT_ENCODING"] = original_encoding if config.suppress_encoding
      end
      return client_settings.handle_cookie([status, headers, body]) if current.discard
      page_struct = current.page_struct
      page_struct[:user] = user(env)
      page_struct[:root].record_time((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000)
      # Original gem's real save/unviewed/injection path, not fabricated cookie
      # or captured headers. A failed source effect must remain detectable.
      begin
        @storage.save(page_struct)
        @storage.set_unviewed(page_struct[:user], page_struct[:id])
        if status >= 200 && status < 300
          result = inject_profiler(env, status, headers, body)
          return client_settings.handle_cookie(result) if result
        end
      rescue Exception => error
        @config.storage_failure.call(error) if @config.storage_failure
        raise
      end
      client_settings.handle_cookie([status, headers, body])
    ensure
      self.current = nil
    end

    def self.rack_response(response)
      headers = {}
      response.headers.size.times do |index|
        headers[response.headers.key_at(index)] = response.headers.val_at(index)
      end
      [response.status, headers, [response.body]]
    end

    def self.subscribe_core_notifications
      ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, start, finish, _id, payload|
        MiniProfiler.record_sql(payload[:sql].to_s, (finish - start) * 1000, nil, payload[:cached])
      end
      ActiveSupport::Notifications.monotonic_subscribe("start_processing.action_controller") do |_name, _start, _finish, _id, payload|
        controller = payload[:controller].to_s.sub(/Controller\z/, "").downcase
        Thread.current[:portable_profiler_action_step] = MiniProfiler.start_step("Executing: " + controller + "#" + payload[:action].to_s)
      end
      ActiveSupport::Notifications.monotonic_subscribe("process_action.action_controller") do |_name, _start, _finish, _id, _payload|
        MiniProfiler.finish_step(Thread.current[:portable_profiler_action_step])
        Thread.current[:portable_profiler_action_step] = nil
      end
      nil
    end
  end
end
