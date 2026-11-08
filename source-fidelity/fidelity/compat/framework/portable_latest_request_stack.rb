# frozen_string_literal: true
require_relative "portable_profiler_middleware"
require_relative "portable_request_processing"
require_relative "portable_json_response_middleware"
require_relative "portable_discourse_request_id_middleware"
require_relative "portable_cors_middleware"
require_relative "portable_host_authorization"
require_relative "portable_remote_ip"
require_relative "portable_json_ingress"
require_relative "portable_json_profile_middleware"
require_relative "portable_query_cache_boundary"

# Supported JSON request bootstrap, not a topic/query backend. The original
# ProcessingRequest scope encloses profiling AND real store effects. Remaining
# original application/framework middleware are still explicitly unaccepted.
class PortableLatestRequestStack
  def self.call(app, env)
    PortableJsonIngress.validate!(env)
    auth_bypass = Middleware::OmniauthBypassMiddleware.new(app)
    crawler = Middleware::CrawlerHooks.new(auth_bypass)
    head = Rack::Head.new(crawler)
    csp = ContentSecurityPolicy::Middleware.new(head)
    nonce = Middleware::CspScriptNonceInjector.new(csp)
    track_view = Middleware::TrackViewSessionIdInjector.new(nonce)
    cors = Discourse::Cors.new(track_view)
    default_headers = Middleware::DefaultHeaders.new(cors)
    remote_ip = ActionDispatch::RemoteIp.new(default_headers)
    request_id = PortableDiscourseRequestIdMiddleware.new(remote_ip)
    method_override = Rack::MethodOverride.new(request_id)
    cache_boundary = PortableQueryCacheBoundary.new(method_override)
    missing_avatars = Middleware::MissingAvatars.new(cache_boundary)
    host_authorization = ActionDispatch::HostAuthorization.new(missing_avatars, PortableHostAuthorizationDeclarations.hosts)
    profiler = Rack::MiniProfiler.new(host_authorization)
    profiled = lambda { |request_env| profiler.call_core(request_env) }
    overload = Middleware::OverloadProtections.new(profiled)
    processing = Middleware::ProcessingRequest.new(overload)
    vary = MarkdownEndpoint::VaryMiddleware.new(processing)
    vary.call(env)
  end
end
