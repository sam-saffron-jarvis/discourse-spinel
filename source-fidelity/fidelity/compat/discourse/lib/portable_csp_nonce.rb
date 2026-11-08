# frozen_string_literal: true
# GENERATED isolated CSP nonce dependency, not policy construction or a request.
require "securerandom"
module PortableResponseMiddlewareDeclarations
  VARY_ACCEPT_ENV_KEY = "discourse.markdown_endpoint.vary_accept"
MAX_SESSION_ID_LENGTH = 32
  # The actual Discourse fast_blank1.0.1 override (rb_isspace or NUL),
  # NOT ActiveSupport's Unicode whitespace blank_as? predicate.
  # Header values outside this Rack profile refuse explicitly.
  def self.blank_header?(value)
    return true if value.nil?
    raise ArgumentError, "unsupported non-string response header profile" unless value.is_a?(String)
    value.match?(/\A[\x00\x09-\x0d\x20]*\z/)
  end
end
module Middleware; class AnonymousCache; CACHEABLE_ENV = "discourse.anonymous_cache.cacheable"; end; end
class ContentSecurityPolicy
def self.nonce_placeholder(response_headers, request_env: nil)
      response_headers[
        ::Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER
      ] ||= if request_env.nil? || request_env[::Middleware::AnonymousCache::CACHEABLE_ENV]
        "[[csp_nonce_placeholder_#{SecureRandom.hex}]]"
      else
        request_env[::Middleware::CspScriptNonceInjector::NONCE_ENV] ||= SecureRandom.alphanumeric(
          25,
        )
      end
    end
end
module UnitCspNonceMethod
def csp_nonce_placeholder
    ContentSecurityPolicy.nonce_placeholder(response.headers, request_env: request.env)
  end
end
# frozen_string_literal: true

module Middleware
  class CspScriptNonceInjector
    NONCE_ENV = "discourse.csp_nonce"
    PLACEHOLDER_HEADER = "Discourse-CSP-Nonce-Placeholder"

    def initialize(app, settings = {})
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      if nonce_placeholder = headers.delete(PLACEHOLDER_HEADER)
        nonce = env[NONCE_ENV] || SecureRandom.alphanumeric(25)
        parts = response
        if !env[NONCE_ENV]
          parts = []
          response.each { |part| parts << part.to_s.gsub(nonce_placeholder, nonce) }
        end
        %w[Content-Security-Policy Content-Security-Policy-Report-Only].each do |name|
          next if PortableResponseMiddlewareDeclarations.blank_header?(headers[name])
          headers[name] = headers[name].sub("script-src ", "script-src 'nonce-#{nonce}' ")
        end
        [status, headers, parts]
      else
        [status, headers, response]
      end
    end
  end
end
