# frozen_string_literal: true
require "set"
# GENERATED supported JSON call-path projections. Optional paths REFUSE.
module Middleware
end
class Middleware::OmniauthBypassMiddleware
def initialize(app, options = {})
    @app = app
  end
def call(env)
return @app.call(env) unless env["PATH_INFO"].start_with?("/auth")
raise ArgumentError, "unsupported JSON profile authentication route"
end

end
class Middleware::MissingAvatars
def initialize(app, settings = {})
      @app = app
    end
def call(env)
if (env["REQUEST_PATH"] =~ %r{\A/uploads/default/avatars})
raise ArgumentError, "unsupported JSON profile missing-avatar route"
end
status, headers, response = @app.call(env)
[status, headers, response]
end

end
class ContentSecurityPolicy
end
class ContentSecurityPolicy::Middleware
def initialize(app)
      @app = app
    end
def call(env)
request = Rack::CoreRequest.new(env)
_, headers, _ = response = @app.call(env)
return response if !PortableResponseMiddlewareDeclarations.blank_header?(headers["Content-Security-Policy"])
return response unless html_response?(headers)
raise ArgumentError, "unsupported JSON profile HTML CSP"
end
def html_response?(headers)
      headers["Content-Type"] && headers["Content-Type"] =~ /html/
    end
end
class Middleware::CrawlerHooks
def initialize(app)
      @app = app
    end
def call(env)
request = Rack::CoreRequest.new(env)
status, headers, response = @app.call(env)
if status == 200 && headers["X-Discourse-Crawler-View"] && headers["Content-Type"]&.include?("text/html")
raise ArgumentError, "unsupported JSON profile crawler HTML"
end
[status, headers, response]
end

end
class Rack::Head
def initialize(app)
      @app = app
    end
def call(env)
status, headers, body = @app.call(env)
if env["REQUEST_METHOD"] == "HEAD"
raise ArgumentError, "unsupported JSON profile HEAD body"
else
[status, headers, body]
end
end

end
class Rack::MethodOverride
def initialize(app)
      @app = app
    end
def call(env)
if allowed_methods.include?(env["REQUEST_METHOD"])
raise ArgumentError, "unsupported JSON profile method override"
end
@app.call(env)
end
ALLOWED_METHODS = %w[POST]
def allowed_methods
      ALLOWED_METHODS
    end
end
module PortableDefaultHeaderConfiguration
def self.default_headers
{
              "X-Frame-Options" => "SAMEORIGIN",
              "X-XSS-Protection" => "0",
              "X-Content-Type-Options" => "nosniff",
              "X-Permitted-Cross-Domain-Policies" => "none",
              "Referrer-Policy" => "strict-origin-when-cross-origin"
            }
end
end
class Middleware::DefaultHeaders
def initialize(app, settings = {})
      @app = app
    end
def call(env)
status, headers, body = @app.call(env)
      is_html_response = html_response?(headers)
      raise ArgumentError, "unsupported JSON profile HTML default headers" if is_html_response

      default_headers =
        PortableDefaultHeaderConfiguration.default_headers.to_h.except(*EXCLUDED_HEADERS)

      default_headers.each do |header_name, value|
        next if !is_html_response && HTML_ONLY_HEADERS.include?(header_name)

        headers[header_name] ||= value
      end


      [status, headers, body]
end
HTML_ONLY_HEADERS = Set.new(%w[X-XSS-Protection])
EXCLUDED_HEADERS = Set.new(%w[X-Frame-Options])
def html_response?(headers)
      headers["Content-Type"] && headers["Content-Type"] =~ /html/
    end
end
