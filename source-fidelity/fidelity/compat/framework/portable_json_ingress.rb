# frozen_string_literal: true
# Admission for the declared direct-loopback GET JSON profile, not a substitute
# for Rails authentication/host/IP checks. Unsupported proxy/server contexts
# fail before profiler, overload, controller or response effects.
class PortableJsonIngress
  FORWARDED_KEYS = %w[HTTP_FORWARDED HTTP_CLIENT_IP].freeze
  HTTP_KEYS = %w[HTTP_HOST HTTP_ACCEPT HTTP_X_REQUEST_ID HTTP_ORIGIN HTTP_X_REQUEST_START
    HTTP_API_KEY HTTP_API_USERNAME HTTP_USER_API_KEY HTTP_USER_API_CLIENT_ID
    HTTP_AUTHORIZATION HTTP_COOKIE].freeze
  SERVER_KEYS = %w[REQUEST_METHOD PATH_INFO QUERY_STRING SERVER_NAME SERVER_PORT SCRIPT_NAME REMOTE_ADDR
    rack.url_scheme action_dispatch.request.parameters _DISCOURSE_CURRENT_USER _DISCOURSE_API
    _DISCOURSE_USER_API _DISCOURSE_DECRYPTED_AUTH_COOKIE].freeze

  # The dispatcher parsed path/query/settings before the test transport's
  # optional headers were supplied. Do not admit a stale parameter/scheme/
  # mount context by overwriting its env without rebuilding the Request.
  def self.validate_overrides!(values)
    values.each do |key, _value|
      raise ArgumentError, "unsupported JSON ingress override key" unless key.is_a?(String)
      allowed = key.start_with?("HTTP_") || key == "REMOTE_ADDR" || key == "REQUEST_METHOD" || key == "PATH_INFO" || key.start_with?("_DISCOURSE_")
      raise ArgumentError, "unsupported JSON ingress parsed-context override" unless allowed
    end
    true
  end

  def self.validate!(env)
    raise ArgumentError, "unsupported JSON ingress method/path" unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/latest.json"
    validate_direct_context!(env)
  end

  # Shared direct-peer/server context checks only. JSON admission above remains
  # exact and unchanged; a separate experimental HTML stage has its own guard.
  def self.validate_direct_context!(env)
    peer = env.fetch("REMOTE_ADDR", nil)
    raise ArgumentError, "unsupported JSON ingress direct peer" unless peer == "127.0.0.1" || peer == "::1"
    env.each do |key, _value|
      raise ArgumentError, "unsupported JSON ingress non-string key" unless key.is_a?(String)
      if key.start_with?("HTTP_X_FORWARDED") || FORWARDED_KEYS.include?(key)
        raise ArgumentError, "unsupported JSON ingress forwarded peer"
      end
      if key.start_with?("HTTP_") && !HTTP_KEYS.include?(key)
        raise ArgumentError, "unsupported JSON ingress HTTP header"
      end
      if key == "action_dispatch.remote_ip" || key == "rack.input" || key == "rack.hijack" || key == "async.callback"
        raise ArgumentError, "unsupported JSON ingress prebound/server context"
      end
      raise ArgumentError, "unsupported JSON ingress server key" unless key.start_with?("HTTP_") || SERVER_KEYS.include?(key)
    end
    scheme = env.fetch("rack.url_scheme", "http")
    raise ArgumentError, "unsupported JSON ingress scheme" unless scheme == "http" || scheme == "https"
    true
  end
end
