# frozen_string_literal: true
# TEST caller only. Actual framework routing, parsing, request, controller and
# response finalization run in process on BOTH identical-lowered runtimes.
require_relative "latest_layout_probe"
require_relative "request_lifecycle_probe"
# TEST observer around the genuine callback. No callback body is replaced;
# the inherited source method still runs through super on the matched route.
class ObservedLatestController < ListController
  def ensure_dont_cache_page
    request.env["fidelity.lifecycle_probe"] = RequestLifecycleProbe.new
    request.env["fidelity.context_and_queries_during_controller"] = request.env["fidelity.lifecycle_probe"].during_controller
    super
  end

  def set_crawler_header
    request.env["fidelity.callback_locale"] = I18n.locale.to_s
    super
  end
end
# Deliberately WRONG TEST consumer, never used by the supported route profile.
# It proves that response/callback checks reject a skipped real callback.
class IgnoredRouteCallbackController < ObservedLatestController
  def set_current_user_for_logs
    nil
  end
end

# Intentionally wrong negative only: omits the real development authorization.
class IgnoredProfilerAuthorizationController < ObservedLatestController
  def authorize_mini_profiler
    nil
  end
end

# Wrong TEST predicate only. The actual source callback must expose its header.
class WrongCrawlerLayoutController < ObservedLatestController
  def use_crawler_layout?
    true
  end
end

# Wrong TEST only: the real requires_login guard is intentionally ignored.
class IgnoredRequiresLoginController < ObservedLatestController
  def block_if_requires_login
    nil
  end
end

# Wrong TEST only: genuine resolver runs, then its result is corrupted.
class WrongThemeController < ObservedLatestController
  def handle_theme
    super
    @theme_id = -987654
  end
end

class IgnoredLayoutPreloaderController < ObservedLatestController
  def initialize_application_layout_preloader
    nil
  end
end

class IgnoredSnapshotFieldsController < ObservedLatestController
  def set_mp_snapshot_fields
    nil
  end
end

class WrongSnapshotFieldsController < ObservedLatestController
  def set_mp_snapshot_fields
    super
    Rack::MiniProfiler.add_snapshot_custom_field("Application version", "deliberately-wrong-test-version")
  end
end

class WrongReadonlyStateController < ObservedLatestController
  def check_readonly_mode
    super
    @readonly_mode = !@readonly_mode
  end
end

class IgnoredReadonlyHeaderController < ObservedLatestController
  def add_readonly_header
    nil
  end
end

class IgnoredLocaleController < ObservedLatestController
  def with_resolved_locale
    yield
  end
end

class WrongLocaleRestoreController < ObservedLatestController
  def with_resolved_locale
    super { yield }
  ensure
    I18n.locale = :en
  end
end


class ObservedRequestQueryScope < ActiveRecord::RequestQueryScope
  def finish_connections
    RequestLifecycleProbe.observe_pool_completion
    super
  end
  def finish_queries
    Thread.current[:fidelity_pool_at_query_completion] = !!ActiveRecord::Base.connection_pool.active_connection?
    super
  end
  def start_context
    Thread.current[:fidelity_context_entry_interlock_depth] = RequestLifecycleProbe.interlock_depth
    super
  end
end
class MissingPoolCompletionScope < ObservedRequestQueryScope
  def finish_connections
    nil
  end
end
class EarlyPoolCompletionScope < ObservedRequestQueryScope
  def finish_queries
    finish_connections
    super
  end
end
class MissingInterlockScope < ObservedRequestQueryScope
  def start_interlock
    nil
  end
end
class LeakedInterlockScope < ObservedRequestQueryScope
  def finish_interlock
    nil
  end
end
class WrongInterlockOrderScope < ObservedRequestQueryScope
  def start_interlock
    nil
  end
  def start_context
    super
    ActiveSupport::Dependencies.interlock.start_running
    @interlock_running = true
    nil
  end
end
class MissingExecutionContextScope < ObservedRequestQueryScope
  def start_context
    nil
  end
end
class MissingQuerySessionScope < ObservedRequestQueryScope
  def start_queries
    nil
  end
end
class LeakedExecutionContextScope < ObservedRequestQueryScope
  def finish_context
    nil
  end
end
class LeakedQuerySessionScope < ObservedRequestQueryScope
  def finish_queries
    nil
  end
end
class PortableQueryCacheBoundary
  def new_scope
    if ENV.fetch("FIDELITY_STAGE4_OMIT_POOL_COMPLETION", "0") == "1"
      MissingPoolCompletionScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_EARLY_POOL_COMPLETION", "0") == "1"
      EarlyPoolCompletionScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_INTERLOCK", "0") == "1"
      MissingInterlockScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_LEAK_INTERLOCK", "0") == "1"
      LeakedInterlockScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_INTERLOCK_ORDER", "0") == "1"
      WrongInterlockOrderScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_EXEC_CONTEXT", "0") == "1"
      MissingExecutionContextScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_QUERY_SESSION", "0") == "1"
      MissingQuerySessionScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_LEAK_EXEC_CONTEXT", "0") == "1"
      LeakedExecutionContextScope.new
    elsif ENV.fetch("FIDELITY_STAGE4_LEAK_QUERY_SESSION", "0") == "1"
      LeakedQuerySessionScope.new
    else
      ObservedRequestQueryScope.new
    end
  end
end

class LatestRequestProbe
  def self.configure_profiler(policy, connection)
    @profiler_policy = policy
    @cache_connection = connection
  end

  def self.call(path, extra_env = {})
    # Actual second pinned locale as ambient thread state: scope must select
    # live application default during callbacks and restore this after unwind.
    I18n.locale = :fr
    RequestLifecycleProbe.before_request
    profile_saves_before = @profiler_policy.profile_save_count
    Rack::MiniProfiler.deauthorize_request
    pieces = path.split("?", 2)
    matched = ActionDispatch::Router.match("GET", pieces[0], RouteTable.table)
    raise ArgumentError, "unsupported test route" unless matched && matched.controller == :list && matched.action == :latest
    params = ParamBuilder.from_query_string(pieces[1].to_s)
    raise ArgumentError, "malformed test query" if params.nil?
    matched.path_params.each { |key, value| params[key] = value }
    request = ActionDispatch::Request.new
    request.request_method = "GET"
    request.path = pieces[0]
    request.query_string = pieces[1].to_s
    hostname = SiteSetting.force_hostname
    hostname = SiteSetting.portable_rendering_hostname if hostname.nil? || hostname.strip.empty?
    default_port = SiteSetting.force_https ? 443 : 80
    port_setting = SiteSetting.port.to_s
    port = port_setting.strip.empty? ? ENV.fetch("UNICORN_PORT", "3000").to_i : port_setting.to_i
    port = default_port unless port > 0
    request.host = hostname + (port == default_port ? "" : ":#{port}")
    request.format = "json"
    request.env["REQUEST_METHOD"] = "GET"
    request.env["PATH_INFO"] = pieces[0]
    request.env["QUERY_STRING"] = pieces[1].to_s
    request.env["HTTP_HOST"] = request.host
    request.env["HTTP_ACCEPT"] = "application/json"
    request.env["SERVER_NAME"] = hostname
    request.env["SERVER_PORT"] = port.to_s
    request.env["SCRIPT_NAME"] = SiteSetting.portable_rendering_base_path
    request.env["REMOTE_ADDR"] = "127.0.0.1"
    request.env["rack.url_scheme"] = SiteSetting.force_https ? "https" : "http"
    params.each { |key, value| request.params[key] = value }
    request.env["action_dispatch.request.parameters"] = request.params
    PortableJsonIngress.validate_overrides!(extra_env)
    extra_env.each { |key, value| request.env[key] = value }
    PortableJsonIngress.validate!(request.env)
    request.host = request.env["HTTP_HOST"].to_s
    request.user_agent = request.env["HTTP_USER_AGENT"].to_s
    controller = if ENV.fetch("FIDELITY_STAGE4_OMIT_ROUTE_CALLBACK", "0") == "1"
      IgnoredRouteCallbackController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_PROFILER_AUTHORIZATION", "0") == "1"
      IgnoredProfilerAuthorizationController.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_CRAWLER", "0") == "1"
      WrongCrawlerLayoutController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_LOGIN_GUARD", "0") == "1"
      IgnoredRequiresLoginController.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_THEME", "0") == "1"
      WrongThemeController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_PRELOADER", "0") == "1"
      IgnoredLayoutPreloaderController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_SNAPSHOT_FIELDS", "0") == "1"
      IgnoredSnapshotFieldsController.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_SNAPSHOT_FIELDS", "0") == "1"
      WrongSnapshotFieldsController.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_READONLY_STATE", "0") == "1"
      WrongReadonlyStateController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_READONLY_HEADER", "0") == "1"
      IgnoredReadonlyHeaderController.new
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_LOCALE", "0") == "1"
      IgnoredLocaleController.new
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_LOCALE_RESTORE", "0") == "1"
      WrongLocaleRestoreController.new
    else
      ObservedLatestController.new
    end
    leaf = lambda do |_env|
      request.env["fidelity.query_cache_enabled_during_controller"] = Db.query_cache_enabled?
      remote_ip = request.env["action_dispatch.remote_ip"]
      request.remote_ip = remote_ip.to_s unless remote_ip.nil?
      request.remote_ip = "203.0.113.99" if ENV.fetch("FIDELITY_STAGE4_WRONG_REMOTE_IP", "0") == "1"
      request.env["fidelity.remote_ip_during_dispatch"] = {value: request.remote_ip,
        lazy_class: remote_ip.nil? ? nil : remote_ip.class.name}
      request.env["action_dispatch.authorized_host"] = "deliberately-wrong.invalid" if ENV.fetch("FIDELITY_STAGE4_WRONG_AUTHORIZED_HOST", "0") == "1"
      request.env["fidelity.authorized_host_during_dispatch"] = request.env["action_dispatch.authorized_host"]
      request.env["fidelity.processing_during_dispatch"] = Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY]
      request.env["fidelity.request_id_during_dispatch"] = request.env["action_dispatch.request_id"]
      request.env["fidelity.cors_origins_during_dispatch"] = request.env[Discourse::Cors::ORIGINS_ENV]
      response = ActionDispatch::InProcessController.dispatch(controller, request, matched,
        etag_middleware: PortableRequestMiddlewarePolicy.etag_middleware?,
        request_id_middleware: ENV.fetch("FIDELITY_STAGE4_LATE_REQUEST_ID", "0") == "1")
      response.headers["Content-Type"] = "text/html" if ENV.fetch("FIDELITY_STAGE4_UNSUPPORTED_MIME", "0") == "1"
      request.env["fidelity.snapshot_fields"] = Rack::MiniProfiler.get_snapshot_custom_fields
      Rack::MiniProfiler.rack_response(response)
    end
    observed_nonce = Middleware::CspScriptNonceInjector.new(leaf)
    observed_track = Middleware::TrackViewSessionIdInjector.new(observed_nonce)
    identified_leaf = PortableDiscourseRequestIdMiddleware.new(ActionDispatch::RemoteIp.new(Discourse::Cors.new(observed_track)))
    authorized_leaf = ActionDispatch::HostAuthorization.new(identified_leaf, PortableHostAuthorizationDeclarations.hosts)
    profiler = Rack::MiniProfiler.new(authorized_leaf)
    profiled = lambda { |env| profiler.call_core(env) }
    if ENV.fetch("FIDELITY_STAGE4_WRONG_HOST_ORDER", "0") == "1"
      # Wrong TEST graph: assigns an ID before the original host guard.
      wrong_host = ActionDispatch::HostAuthorization.new(Discourse::Cors.new(observed_track), PortableHostAuthorizationDeclarations.hosts)
      wrong_outer_id = PortableDiscourseRequestIdMiddleware.new(wrong_host)
      wrong_host_profiler = Rack::MiniProfiler.new(wrong_outer_id)
      wrong_host_profiled = lambda { |env| wrong_host_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(wrong_host_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_QUERY_CACHE", "0") == "1" || ENV.fetch("FIDELITY_STAGE4_EARLY_QUERY_CACHE_COMPLETE", "0") == "1"
      cache_fault_leaf = lambda do |env|
        if ENV.fetch("FIDELITY_STAGE4_EARLY_QUERY_CACHE_COMPLETE", "0") == "1"
          # Wrong TEST graph: reproduce a completion before the action, with
          # identical successful payloads but no request cache lifecycle.
          fault_scope = ActiveRecord::QueryCacheScope.new
          fault_scope.complete!
        end
        leaf.call(env)
      end
      fault_nonce = Middleware::CspScriptNonceInjector.new(cache_fault_leaf)
      fault_track = Middleware::TrackViewSessionIdInjector.new(fault_nonce)
      fault_cors = Discourse::Cors.new(fault_track)
      fault_peer = ActionDispatch::RemoteIp.new(fault_cors)
      fault_id = PortableDiscourseRequestIdMiddleware.new(fault_peer)
      fault_host = ActionDispatch::HostAuthorization.new(fault_id, PortableHostAuthorizationDeclarations.hosts)
      fault_profiler = Rack::MiniProfiler.new(fault_host)
      fault_profiled = lambda { |env| fault_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(fault_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_REMOTE_IP", "0") == "1"
      omitted_ip = PortableDiscourseRequestIdMiddleware.new(Discourse::Cors.new(observed_track))
      omitted_ip_host = ActionDispatch::HostAuthorization.new(omitted_ip, PortableHostAuthorizationDeclarations.hosts)
      omitted_ip_profiler = Rack::MiniProfiler.new(omitted_ip_host)
      omitted_ip_profiled = lambda { |env| omitted_ip_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(omitted_ip_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_LATE_REMOTE_IP", "0") == "1"
      late_ip_leaf = lambda do |env|
        result = leaf.call(env)
        ActionDispatch::RemoteIp.new(lambda { |_same| result }).call(env)
      end
      # Wrong TEST graph: compute/install the peer only after controller entry.
      nonce = Middleware::CspScriptNonceInjector.new(late_ip_leaf)
      track = Middleware::TrackViewSessionIdInjector.new(nonce)
      late_id = PortableDiscourseRequestIdMiddleware.new(Discourse::Cors.new(track))
      late_host = ActionDispatch::HostAuthorization.new(late_id, PortableHostAuthorizationDeclarations.hosts)
      late_profiler = Rack::MiniProfiler.new(late_host)
      late_profiled = lambda { |env| late_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(late_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_HOST_AUTHORIZATION", "0") == "1"
      # Deliberately wrong TEST graph: all consumers except real host guard.
      no_host_profiler = Rack::MiniProfiler.new(identified_leaf)
      no_host_profiled = lambda { |env| no_host_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(no_host_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_CORS", "0") == "1"
      # Wrong TEST graph: preserve ID/body injectors, omit actual CORS only.
      without_cors = PortableDiscourseRequestIdMiddleware.new(ActionDispatch::RemoteIp.new(observed_track))
      no_cors_authorized = ActionDispatch::HostAuthorization.new(without_cors, PortableHostAuthorizationDeclarations.hosts)
      no_cors_profiler = Rack::MiniProfiler.new(no_cors_authorized)
      no_cors_profiled = lambda { |env| no_cors_profiler.call_core(env) }
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(no_cors_profiled))).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_REQUEST_ID", "0") == "1" || ENV.fetch("FIDELITY_STAGE4_LATE_REQUEST_ID", "0") == "1"
      # Deliberately wrong TEST graph: absent, or synthesized only on return.
      # inside the controller or bind the same ID to the response afterwards.
      nonce = Middleware::CspScriptNonceInjector.new(leaf)
      track = Middleware::TrackViewSessionIdInjector.new(nonce)
      omitted_authorized = ActionDispatch::HostAuthorization.new(ActionDispatch::RemoteIp.new(Discourse::Cors.new(track)), PortableHostAuthorizationDeclarations.hosts)
      omitted_profiler = Rack::MiniProfiler.new(omitted_authorized)
      omitted_profiled = lambda { |env| omitted_profiler.call_core(env) }
      omitted_overload = Middleware::OverloadProtections.new(omitted_profiled)
      status, headers, body = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(omitted_overload)).call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_WRONG_PROCESSING_ORDER", "0") == "1"
      # Deliberately wrong TEST graph: prior implementation cleared processing
      # before the profiler saved. Exact original executed stack disproved it.
      wrong_inner = Middleware::ProcessingRequest.new(authorized_leaf)
      wrong_profiler = Rack::MiniProfiler.new(lambda { |env| wrong_inner.call(env) })
      status, headers, body = wrong_profiler.call_core(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_PROCESSING", "0") == "1"
      status, headers, body = profiled.call(request.env)
    elsif ENV.fetch("FIDELITY_STAGE4_OMIT_OVERLOAD", "0") == "1"
      ignored_overload = Middleware::ProcessingRequest.new(profiled)
      status, headers, body = ignored_overload.call(request.env)
    else
      # Original ProcessingRequest is OUTSIDE MiniProfiler, including storage
      # writes and all its ensure paths, not merely controller dispatch.
      status, headers, body = PortableLatestRequestStack.call(leaf, request.env)
    end
    if status == 503
      return {path: path, status: status, headers: headers, body: body.join,
        request_effects: {controller_dispatched: !request.env["fidelity.processing_during_dispatch"].nil?,
          profiler_saved: @profiler_policy.profile_save_count != profile_saves_before,
          processing_after_dispatch: Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY],
          queue_above_threshold: request.env[Middleware::ProcessingRequest::REQUEST_QUEUE_SECONDS_ENV_KEY].to_f > SiteSetting.portable_reject_anonymous_min_queue_seconds}}
    end
    headers["Access-Control-Allow-Origin"] = "https://wrong-test-origin.invalid" if ENV.fetch("FIDELITY_STAGE4_WRONG_CORS_ORIGIN", "0") == "1"
    proof = LatestProfilerStoreProbe.call(@profiler_policy, headers)
    effects = {processing_during_dispatch: request.env["fidelity.processing_during_dispatch"],
      processing_during_profiler_save: @profiler_policy.processing_during_profile_save,
      processing_after_dispatch: Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY],
      profiler_authorized_after_dispatch: Rack::MiniProfiler.request_authorized?,
      application_layout_preloader: LatestLayoutProbe.capture(controller),
      profiler_snapshot_fields: request.env["fidelity.snapshot_fields"],
      readonly_state: LatestLayoutProbe.readonly_state(controller),
      request_locale: {during_callbacks: request.env["fidelity.callback_locale"], after_dispatch: I18n.locale.to_s},
      cors_origins_during_dispatch: request.env["fidelity.cors_origins_during_dispatch"],
      authorized_host_during_dispatch: request.env["fidelity.authorized_host_during_dispatch"],
      remote_ip_during_dispatch: request.env["fidelity.remote_ip_during_dispatch"],
      request_id_visible_and_consistent: !request.env["fidelity.request_id_during_dispatch"].nil? &&
        request.env["fidelity.request_id_during_dispatch"] == headers["X-Request-Id"]}
    begin
      body_text = body.join
    ensure
      body.close if body.respond_to?(:close)
    end
    puts "FIDELITY_CANDIDATE_REQUEST_LIFECYCLE " + JSON.generate({
      query_cache_enabled_during_controller: request.env["fidelity.query_cache_enabled_during_controller"],
      query_cache_enabled_after_response: Db.query_cache_enabled?,
      context_and_queries_during_controller: request.env["fidelity.context_and_queries_during_controller"],
      context_and_queries_after_response: request.env["fidelity.lifecycle_probe"].after_response})
    {path: path, status: status, headers: headers, body: JSON.parse(body_text), profiler_proof: proof, request_effects: effects}
  rescue ArgumentError => error
    if error.message == "unsupported blocked-host JSON request profile"
      host_order_proof = {request_id_assigned: !request.env["action_dispatch.request_id"].nil?,
        cors_entered: !request.env[Discourse::Cors::ORIGINS_ENV].nil?,
        controller_entered: !request.env["fidelity.processing_during_dispatch"].nil?,
        blocked_hosts: request.env["action_dispatch.blocked_hosts"],
        context_cleanup: ActionController::Current.request.nil? && ActionController::Current.controller.nil? &&
          Rack::MiniProfiler.current.nil? && Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?}
      puts "FIDELITY_BLOCKED_HOST_ORDER_PROOF " + JSON.generate(host_order_proof)
      raise "blocked-host request ID ran before authorization" if host_order_proof[:request_id_assigned]
      raise "blocked-host CORS ran before authorization" if host_order_proof[:cors_entered]
      raise "blocked-host entered controller" if host_order_proof[:controller_entered]
      raise "blocked-host leaked context" unless host_order_proof[:context_cleanup]
    end
    if ENV.fetch("FIDELITY_STAGE4_OMIT_LOCALE", "0") == "1" && error.message == "unsupported list locale"
      raise "omitted locale leaked controller context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
      raise "omitted locale leaked profiler context" unless Rack::MiniProfiler.current.nil?
      raise "omitted locale leaked processing context" unless Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?
      raise "ambient locale unexpectedly changed" unless I18n.locale == :fr
      puts "FIDELITY_IGNORED_LOCALE_REFUSAL " + JSON.generate({source_guard: error.message, context_cleanup: true, ambient_locale: I18n.locale.to_s})
    end
    raise
  end
end

# TEST-only live flag mutations in the guarded disposable owned cache. The
# application readers never consult these labels and never receive a mode map.
class LatestRequestProbe
  def self.clear_readonly_case
    keys = PortableReadonlyState::READONLY_KEYS + [PortableReadonlyState::STAFF_WRITES_ONLY_MODE_KEY, PortableReadonlyState::LAST_POSTGRES_READONLY_KEY]
    qualified = keys.map { |key| PortableReadonlyContext.redis.namespace_key(key) }
    @cache_connection.call(["DEL", *qualified])
    PortableReadonlyContext.clear_redis_readonly!
  end

  def self.run_readonly_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_READONLY_MATRIX", "0") == "1"
    begin
      ["site", "staff", "recent-pg", "stale-pg", "local-error", "cleared", "site-invalid-page"].each do |profile|
        clear_readonly_case
        key = nil
        value = "1"
        case profile
        when "site", "site-invalid-page" then key = PortableReadonlyState::READONLY_MODE_KEY
        when "staff" then key = PortableReadonlyState::STAFF_WRITES_ONLY_MODE_KEY
        when "recent-pg"
          key = PortableReadonlyState::LAST_POSTGRES_READONLY_KEY
          value = Time.now.to_i.to_s
        when "stale-pg"
          key = PortableReadonlyState::LAST_POSTGRES_READONLY_KEY
          value = (Time.now.to_i - 60).to_s
        when "local-error" then PortableReadonlyContext.received_redis_readonly!
        end
        @cache_connection.setex(PortableReadonlyContext.redis.namespace_key(key), 60, value) if key
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

class LatestRequestProbe
  def self.run_remote_ip_matrix
    return unless ENV.fetch("FIDELITY_STAGE4_MIDDLEWARE_MATRIX", "0") == "1"
    puts "FIDELITY_REMOTE_IP_REQUEST " + JSON.generate({profile: "direct-ipv6", request: call("/latest.json", {"REMOTE_ADDR" => "::1"})})
  end
end
