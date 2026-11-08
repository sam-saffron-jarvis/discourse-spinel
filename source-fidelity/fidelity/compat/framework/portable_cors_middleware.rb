# frozen_string_literal: true
# GENERATED original CORS algorithm; configuration/store stay live.
module PortableCorsReadContext
  def self.site_origins
    value = SiteSetting.cors_origins
    raise ArgumentError, "unsupported non-string site CORS origins" unless value.is_a?(String)
    value
  end
end
class Discourse::Cors
  ORIGINS_ENV = "Discourse_Cors_Origins"

  def initialize(app, options = nil)
    @app = app
    if SiteSetting.portable_cors_enabled? && !PortableResponseMiddlewareDeclarations.blank_header?(SiteSetting.portable_cors_origin)
      @global_origins = SiteSetting.portable_cors_origin.to_s.split(",").map { |x| x.strip.chomp("/") }
    end
  end

  def call(env)
    return @app.call(env) if !SiteSetting.portable_cors_enabled? && !SiteSetting.portable_rendering_asset_host

    cors_origins = @global_origins || []
    cors_origins += PortableCorsReadContext.site_origins.split("|") if !PortableResponseMiddlewareDeclarations.blank_header?(PortableCorsReadContext.site_origins)
    cors_origins = cors_origins.empty? ? nil : cors_origins

    if env["REQUEST_METHOD"] == "OPTIONS" && env["HTTP_ACCESS_CONTROL_REQUEST_METHOD"]
      return 200, Discourse::Cors.apply_headers(cors_origins, env, {}), []
    end

    env[Discourse::Cors::ORIGINS_ENV] = cors_origins if cors_origins

    status, headers, body = @app.call(env)
    headers ||= {}

    Discourse::Cors.apply_headers(cors_origins, env, headers)

    [status, headers, body]
  end

  def self.apply_headers(cors_origins, env, headers)
    if headers["Access-Control-Allow-Origin"]
      # Already configured. Probably by ApplicationController#apply_cdn_headers
    elsif cors_origins
      origin = env["HTTP_ORIGIN"]
      origin = nil if origin && !cors_origins.include?(origin)

      headers["Access-Control-Allow-Origin"] = origin || cors_origins[0]
      headers[
        "Access-Control-Allow-Headers"
      ] = "Content-Type, Cache-Control, X-Requested-With, X-CSRF-Token, Discourse-Present, User-Api-Key, User-Api-Client-Id, Authorization"
      headers["Access-Control-Allow-Credentials"] = "true"
      headers["Access-Control-Allow-Methods"] = "POST, PUT, GET, OPTIONS, DELETE"
      headers["Access-Control-Max-Age"] = "7200"
    end

    headers
  end
end
