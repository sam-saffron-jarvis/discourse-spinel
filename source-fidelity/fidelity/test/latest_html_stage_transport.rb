# frozen_string_literal: true
# TEST transport: real admitted HTML Request and source callbacks/query only.
# Never synthesize/return a response from the rendering refusal.
require_relative "latest_request_transport"
class HtmlStageMiniProfiler < Rack::MiniProfiler
  def validate_core_profile!(env)
    raise ArgumentError, "unsupported HTML stage profiler route" unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/latest"
    validate_direct_context!(env)
  end
end
class HtmlStageObservedController < ObservedLatestController
  attr_reader :html_events
  def ensure_dont_cache_page
    @html_events = []
    super
  end
  def preload_json
    super
    @html_events << "preload_marker"
  end
  def initialize_application_layout_preloader
    super
    @html_events << "preloader_constructor"
  end
  def latest
    @html_events << "action"
    super
  end
  def respond_with_list(list)
    @html_events << "responder"
    super
  end
end
class HtmlMissingMarkerController < HtmlStageObservedController
  def preload_json
    @html_events << "preload_marker"
  end
end
class HtmlMissingStorageController < HtmlStageObservedController
  def store_preloaded(key, json)
    nil
  end
end
class HtmlDuplicateMarkerController < HtmlStageObservedController
  def initialize_application_layout_preloader
    preload_json
    super
  end
end
class HtmlWrongThemeController < HtmlStageObservedController
  def handle_theme
    super
    @theme_id = -987654
  end
end
class LatestHtmlStageProbe
  def self.compare_isolated_original(request, controller, stored)
    nil
  end
  def self.call(path, extra_env = {})
    I18n.locale = :fr
    RequestLifecycleProbe.before_request
    pieces = path.split("?", 2)
    matched = ActionDispatch::Router.match("GET", pieces[0], RouteTable.table)
    raise ArgumentError, "unsupported HTML stage route" unless matched && matched.controller == :list && matched.action == :latest
    params = ParamBuilder.from_query_string(pieces[1].to_s)
    raise ArgumentError, "unsupported HTML stage query" unless params
    raise ArgumentError, "unsupported HTML stage format override" if params.key?("format")
    matched.path_params.each { |key, value| params[key] = value }
    request = ActionDispatch::Request.new
    request.request_method = "GET"
    request.path = pieces[0]
    request.query_string = pieces[1].to_s
    request.format = "html"
    hostname = SiteSetting.force_hostname
    hostname = SiteSetting.portable_rendering_hostname if hostname.nil? || hostname.strip.empty?
    default_port = SiteSetting.force_https ? 443 : 80
    port_setting = SiteSetting.port.to_s
    port = port_setting.strip.empty? ? ENV.fetch("UNICORN_PORT", "3000").to_i : port_setting.to_i
    port = default_port unless port > 0
    request.host = hostname + (port == default_port ? "" : ":#{port}")
    request.env["REQUEST_METHOD"] = "GET"
    request.env["PATH_INFO"] = pieces[0]
    request.env["QUERY_STRING"] = pieces[1].to_s
    request.env["HTTP_HOST"] = request.host
    request.env["HTTP_ACCEPT"] = "text/html"
    request.env["SERVER_NAME"] = hostname
    request.env["SERVER_PORT"] = port.to_s
    request.env["SCRIPT_NAME"] = SiteSetting.portable_rendering_base_path
    request.env["REMOTE_ADDR"] = "127.0.0.1"
    request.env["rack.url_scheme"] = SiteSetting.force_https ? "https" : "http"
    params.each { |key, value| request.params[key] = value }
    request.env["action_dispatch.request.parameters"] = request.params
    PortableJsonIngress.validate_overrides!(extra_env)
    extra_env.each { |key, value| request.env[key] = value }
    PortableHtmlStageIngress.validate!(request.env)
    # Keep the materialized Request in sync with admitted Rack header overrides;
    # HostAuthorization below still decides whether that host is permitted.
    request.host = request.env["HTTP_HOST"].to_s
    fault = ENV.fetch("FIDELITY_HTML_STAGE_FAULT", "")
    controller = case fault
      when "missing-marker" then HtmlMissingMarkerController.new
      when "missing-storage" then HtmlMissingStorageController.new
      when "duplicate-marker" then HtmlDuplicateMarkerController.new
      when "wrong-theme" then HtmlWrongThemeController.new
      else HtmlStageObservedController.new
    end
    leaf = lambda do |_env|
      remote_ip = request.env["action_dispatch.remote_ip"]
      request.remote_ip = remote_ip.to_s unless remote_ip.nil?
      ActionDispatch::InProcessController.dispatch(controller, request, matched, etag_middleware: false, request_id_middleware: false)
      raise "HTML rendering refusal was bypassed"
    end
    nonce = Middleware::CspScriptNonceInjector.new(leaf)
    track = Middleware::TrackViewSessionIdInjector.new(nonce)
    identified = PortableDiscourseRequestIdMiddleware.new(ActionDispatch::RemoteIp.new(Discourse::Cors.new(track)))
    authorized = ActionDispatch::HostAuthorization.new(identified, PortableHostAuthorizationDeclarations.hosts)
    profiler = HtmlStageMiniProfiler.new(authorized)
    profile = lambda { |env| profiler.call_core(env) }
    stack = MarkdownEndpoint::VaryMiddleware.new(Middleware::ProcessingRequest.new(Middleware::OverloadProtections.new(profile)))
    scoped = PortableQueryCacheBoundary.new(stack)
    begin
      scoped.call(request.env)
      raise "HTML stage fabricated a response"
    rescue HtmlRenderingBoundary => error
      raise "HTML callback/action order changed" unless controller.html_events == ["preload_marker", "preloader_constructor", "action", "responder"]
      preloaded = controller.instance_variable_get(:@_preloaded)
      preloader = controller.instance_variable_get(:@application_layout_preloader)
      stored = preloader.instance_variable_get(:@preloaded)
      list = controller.html_stage_list
      raise "HTML-specific preload marker missing" unless preloaded.is_a?(Hash) && preloaded.empty?
      raise "HTML stage lacks genuine list" unless list.is_a?(TopicList) && !list.topics.empty?
      raise "HTML stage used fake Site data" unless stored.keys == [list.preload_key]
      raise "HTML theme acquisition result changed" unless preloader.instance_variable_get(:@theme_id) == request.env["discourse.resolved_theme_id"]
      raise "HTML callback locale changed" unless request.env["fidelity.callback_locale"] == SiteSetting.default_locale
      parsed = JSON.parse(stored[list.preload_key])
      raise "derived HTML topic payload missing" unless parsed["topic_list"]["topics"].map { |topic| topic["id"] } == list.topics.map(&:id)
      raise "controller/locale/profiler context leaked" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil? && I18n.locale == :fr && Rack::MiniProfiler.current.nil?
      lifecycle = request.env["fidelity.lifecycle_probe"]
      cleanup = lifecycle.after_response
      raise "HTML exception leaked execution/query scope" unless cleanup.values.all? { |value| value == true }
      # Explicit UNIT-only safety regression on a NEW real preloader, never
      # supplied to the request or represented as acquired production data.
      unit = ApplicationLayoutPreloader.new(guardian: controller.guardian, theme_id: nil, theme_target: :desktop, login_method: nil)
      unit.store_preloaded("unit-only", '{"unit-only":"</script>"}')
      raise "HTML preloader script closer not escaped" unless unit.instance_variable_get(:@preloaded)["unit-only"] == '{"unit-only":"<\\/script>"}'
      original = compare_isolated_original(request, controller, stored)
      {original_methods: original, callback_order: controller.html_events, path: path, format: request.format, refused: true, refusal: error.message,
        html_preload_marker: true, genuine_topic_ids: list.topics.map(&:id), derived_preloads: stored,
        title: controller.instance_variable_get(:@title), description: controller.instance_variable_get(:@description),
        rss: controller.instance_variable_get(:@rss), layout: LatestLayoutProbe.capture(controller), cleanup: cleanup,
        route_header: controller.response.headers["X-Discourse-Route"], request_id: request.env["action_dispatch.request_id"],
        site_acquired: false, html200: false, page_accepted: false}
    end
  end
end
