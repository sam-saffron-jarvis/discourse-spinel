# frozen_string_literal: true
# GENERATED genuine response middleware; all other stack entries unaccepted.
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
# frozen_string_literal: true

module MarkdownEndpoint
  class VaryMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      return status, headers, body unless env[PortableResponseMiddlewareDeclarations::VARY_ACCEPT_ENV_KEY]

      headers = headers.dup
      vary_key = headers.keys.find { |key| key.casecmp?("Vary") } || "Vary"
      tokens = headers[vary_key].to_s.split(",").map(&:strip).reject { |token| PortableResponseMiddlewareDeclarations.blank_header?(token) }
      tokens << "Accept" unless tokens.any? { |token| token.casecmp?("Accept") }
      headers[vary_key] = tokens.join(", ")

      [status, headers, body]
    end
  end
end

# frozen_string_literal: true

module Middleware
  class TrackViewSessionIdInjector
    PLACEHOLDER_HEADER = "Discourse-Track-View-Session-Id-Placeholder"

    def initialize(app, settings = {})
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      if placeholder = headers.delete(PLACEHOLDER_HEADER)
        session_id = SecureRandom.alphanumeric(PortableResponseMiddlewareDeclarations::MAX_SESSION_ID_LENGTH)
        parts = []
        response.each { |part| parts << part.to_s.sub(placeholder, session_id) }
        [status, headers, parts]
      else
        [status, headers, response]
      end
    end
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

