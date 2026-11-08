# frozen_string_literal: true
require_relative "portable_profiler_middleware"
require_relative "portable_profiler_declarations"
require_relative "portable_request_processing"
require_relative "portable_latest_request_stack"

# Shared application bootstrap for the operative profiler5 JSON profile. Values
# come from live application configuration and original initializer declarations,
# never a captured effective settings map. Unsupported snapshots refuse rather
# than forcing the live setting off or starting an external transporter.
module PortableProfilerBootstrap
  def self.configure(global_configuration, connection)
    raise ArgumentError, "unsupported non-development profiler request profile" unless ENV.fetch("RAILS_ENV") == "development"
    Rails.env_name = ENV.fetch("RAILS_ENV")
    config = Rack::MiniProfiler.config
    config.storage_instance = Rack::MiniProfiler::RedisStore.new(
      connection: connection, expires_in: ENV["DISCOURSE_MINI_PROFILER_STORAGE_EXPIRY_SECONDS"]&.to_i)
    config.snapshot_every_n_requests = global_configuration.value("mini_profiler_snapshots_period")
    config.snapshots_transport_destination_url = global_configuration.value("mini_profiler_snapshots_transport_url")
    config.snapshots_transport_auth_key = global_configuration.value("mini_profiler_snapshots_transport_auth_key")
    raise ArgumentError, "unsupported configured profiler snapshot/transporter profile" unless config.snapshot_every_n_requests == 0 && !Rack::MiniProfiler.snapshots_transporter?
    config.pre_authorize_cb = lambda { |env| env["HTTP_USER_AGENT"] !~ /iPad|iPhone|Android/ }
    config.user_provider = lambda do |env|
      request = Rack::CoreRequest.new(env)
      id = request.cookies["_t"] || request.ip || "unknown"
      Digest::MD5.hexdigest(id.to_s)
    end
    base_path = SiteSetting.portable_rendering_base_path
    config.cookie_path = base_path.empty? ? "/" : base_path
    config.skip_paths = PortableProfilerDeclarations.skip_paths(base_path)
    config.position = "right"
    config.backtrace_ignores ||= []
    config.backtrace_ignores << %r{lib/rack/message_bus.rb}
    config.backtrace_ignores << %r{config/initializers/silence_logger}
    config.backtrace_ignores << %r{config/initializers/quiet_logger}
    config.backtrace_includes = [%r{^/?(app|config|lib|test|plugins)}]
    config.max_traces_to_show = 100 if Rails.env.development?
    config.logger = Rails.logger
    Rack::MiniProfiler.subscribe_core_notifications
    nil
  end
end
