# frozen_string_literal: true
require_relative "serialized_latest_reference_consumer"
require "rack/mock"
require_relative "latest_profiler_reference_probe"
# TEST transport for the unmodified Rails app. The native and same-lowered
# runtimes use their actual framework in-process dispatcher; neither loads this oracle transport.
class LatestRequestProbe
  def self.call(path, extra_env = {})
    url = URI.parse(Discourse.base_url + path)
    host = url.host + (url.default_port == url.port ? "" : ":#{url.port}")
    request_env = Rack::MockRequest.env_for(url.to_s,
      "HTTP_HOST" => host, "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json")
    request_env.merge!(extra_env)
    response, proof, effects = LatestProfilerReferenceProbe.capture(request_env) do
      Rack::MockRequest.new(Rails.application).get(url.to_s, request_env)
    end
    body = response.status == 503 ? response.body : JSON.parse(response.body)
    {path: path, status: response.status, headers: response.headers.to_h, body: body, profiler_proof: proof, request_effects: effects}
  end
end

# TEST-only invalid credentials on the genuine ORIGINAL framework, after the
# positive matrix so their profiler IDs do not alter its independent cache pool.
at_exit do
  if $!.nil?
    %w[HTTP_API_KEY HTTP_USER_API_KEY].each do |header|
      url = URI.parse(Discourse.base_url + "/latest.json")
      host = url.host + (url.default_port == url.port ? "" : ":#{url.port}")
      env = Rack::MockRequest.env_for(url.to_s, "HTTP_HOST" => host, "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_ACCEPT" => "application/json", header => "invalid-stage4-test-key")
      response = Rack::MockRequest.new(Rails.application).get(url.to_s, env)
      raise "original accepted invalid API credentials" unless response.status >= 400 && response.status < 500
      body = JSON.parse(response.body)
      raise "original disclosed topics after invalid credentials" if body.key?("topic_list")
      puts "FIDELITY_CREDENTIAL_REFERENCE " + JSON.generate({header: header, status: response.status,
        headers: response.headers.to_h, body: body, refused: true})
    end
  end
end

# TEST-only exact same live readonly cases, using original public APIs on its
# separately owned cache. No modes/settings are forced in application code.
class LatestRequestProbe
  def self.clear_readonly_case
    Discourse.redis.del(*(Discourse::READONLY_KEYS + [Discourse::STAFF_WRITES_ONLY_MODE_KEY, Discourse::LAST_POSTGRES_READONLY_KEY]))
    Discourse.clear_redis_readonly!
    Discourse.postgres_last_read_only.clear(after_commit: false)
  end

  def self.run_readonly_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_READONLY_MATRIX", "0") == "1"
    begin
      ["site", "staff", "recent-pg", "stale-pg", "local-error", "cleared", "site-invalid-page"].each do |profile|
        clear_readonly_case
        key = nil
        value = "1"
        case profile
        when "site", "site-invalid-page" then key = Discourse::READONLY_MODE_KEY
        when "staff" then key = Discourse::STAFF_WRITES_ONLY_MODE_KEY
        when "recent-pg"
          key = Discourse::LAST_POSTGRES_READONLY_KEY
          value = Time.now.to_i.to_s
        when "stale-pg"
          key = Discourse::LAST_POSTGRES_READONLY_KEY
          value = (Time.now.to_i - 60).to_s
        when "local-error" then Discourse.received_redis_readonly!
        end
        Discourse.redis.setex(key, 60, value) if key
        puts "FIDELITY_READONLY_REQUEST " + JSON.generate({profile: profile, request: call(profile == "site-invalid-page" ? "/latest.json?page=not-an-integer" : "/latest.json")})
      end
    ensure
      clear_readonly_case
    end
  end
end

class LatestRequestProbe
  def self.run_overload_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    {"seconds" => "t=1", "milliseconds" => "1000"}.each do |profile, header|
      puts "FIDELITY_OVERLOAD_REQUEST " + JSON.generate({profile: profile,
        request: call("/latest.json", {"HTTP_X_REQUEST_START" => header})})
    end
  end
end

class LatestRequestProbe
  def self.run_request_id_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    {"supplied" => "01234567-0123-4567-89ab-0123456789ab!!", "unicode-blank" => "\u00a0"}.each do |profile, header|
      puts "FIDELITY_REQUEST_ID_REQUEST " + JSON.generate({profile: profile,
        request: call("/latest.json", {"HTTP_X_REQUEST_ID" => header})})
    end
  end
end

class LatestRequestProbe
  def self.run_cors_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    {"absent" => nil, "allowed" => "https://cors-b.invalid", "disallowed" => "https://not-configured.invalid"}.each do |profile, origin|
      headers = {}
      headers["HTTP_ORIGIN"] = origin if origin
      puts "FIDELITY_CORS_REQUEST " + JSON.generate({profile: profile, request: call("/latest.json", headers)})
    end
  end
end

class LatestRequestProbe
  def self.run_host_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    {"nested-localhost" => "a.b.localhost:3000", "test-domain" => "one.test:3000",
     "ipv4" => "127.0.0.1:3000", "ipv6" => "[2001:db8::1]:3000"}.each do |profile, authority|
      puts "FIDELITY_HOST_REQUEST " + JSON.generate({profile: profile,
        request: call("/latest.json", {"HTTP_HOST" => authority})})
    end
  end
end

# TEST-only actual original host rejection. Observe the middleware's real env
# (Rack clones caller options) and real callback entry, not a caller-side marker.
at_exit do
  if $!.nil?
    callbacks = ListController._process_action_callbacks.map(&:filter).select { |filter| filter.is_a?(Symbol) }
    entered_callbacks = []
    blocked_hosts = nil
    actual_host_env = nil
    trace = TracePoint.new(:call, :return) do |event|
      if event.event == :call && callbacks.include?(event.method_id) && event.path.start_with?(File.expand_path(".") + "/")
        entered_callbacks << event.method_id
      end
      if event.path.end_with?("/action_dispatch/middleware/host_authorization.rb")
        blocked_hosts = event.return_value if event.event == :return && event.method_id == :blocked_hosts
        if event.event == :return && event.method_id == :call && event.binding.local_variable_defined?(:env)
          env = event.binding.local_variable_get(:env)
          actual_host_env = {blocked: env["action_dispatch.blocked_hosts"], authorized: env["action_dispatch.authorized_host"]}
        end
      end
    end
    url = URI.parse(Discourse.base_url + "/latest.json")
    env = Rack::MockRequest.env_for(url.to_s, "HTTP_HOST" => "attacker.invalid", "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json")
    Rack::MiniProfiler.deauthorize_request
    begin
      trace.enable
      response = Rack::MockRequest.new(Rails.application).get(url.to_s, env)
    ensure
      trace.disable
    end
    raise "original host guard did not reject" unless response.status == 403
    raise "original blocked host entered controller" unless entered_callbacks.empty?
    raise "original classifier/env proof missing" unless blocked_hosts == ["attacker.invalid"] && actual_host_env == {blocked: ["attacker.invalid"], authorized: nil}
    puts "FIDELITY_HOST_REFERENCE " + JSON.generate({status: response.status, headers: response.headers.to_h, body: response.body,
      blocked_hosts: blocked_hosts, actual_middleware_env: actual_host_env, entered_callbacks: entered_callbacks})
  end
end

class LatestRequestProbe
  def self.run_remote_ip_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    puts "FIDELITY_REMOTE_IP_REQUEST " + JSON.generate({profile: "direct-ipv6", request: call("/latest.json", {"REMOTE_ADDR" => "::1"})})
  end
end
