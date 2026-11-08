# frozen_string_literal: true
# TEST-only observations of actual original profiler storage and headers. Never
# loaded by the candidate/native runtime; no oracle data is an execution input.
require_relative "../test/latest_layout_probe"
require_relative "../test/request_lifecycle_probe"
class RequestLifecycleProbe
  def self.interlock_depth
    ActiveSupport::Dependencies.interlock.raw_state do |state|
      state.fetch(Thread.current, {}).fetch(:sharing, 0)
    end
  end
end
module LatestProfilerReferenceProbe
  # Read-only TEST attestation of real framework lifecycle contracts. This is
  # never loaded by native/compat code and supplies no runtime inputs to them.
  def self.lifecycle_callbacks(klass, event)
    klass.public_send("_#{event}_callbacks").map do |callback|
      filter = callback.filter
      unless filter.is_a?(Symbol) || filter.is_a?(Proc)
        hook = filter.respond_to?(:hook) ? filter.hook : filter.instance_variable_get(:@hook)
      end
      location = if filter.is_a?(Symbol)
        klass.instance_method(filter).source_location
      elsif filter.is_a?(Proc)
        filter.source_location
      elsif hook && hook.respond_to?(event)
        hook.method(event).source_location
      end
      {kind: callback.kind.to_s, filter_class: filter.class.name,
        filter: filter.is_a?(Symbol) ? filter.to_s : nil,
        hook: hook.is_a?(Module) ? hook.name : hook&.class&.name,
        source_location: location, source_sha256: location && File.file?(location[0]) ? Digest::SHA256.file(location[0]).hexdigest : nil}
    end
  end

  def self.capture(env)
    # Isolate each observation from the prior request's real thread authorization.
    # This is an original profiler API call by the TEST driver, not app behavior.
    I18n.locale = :fr
    Rack::MiniProfiler.deauthorize_request
    current_id = nil
    processing_seen = nil
    processing_during_save = nil
    layout_state = nil
    snapshot_fields = nil
    readonly_state = nil
    callback_locale = nil
    request_id_during_dispatch = nil
    cors_origins_during_dispatch = nil
    authorized_host_during_dispatch = nil
    remote_ip_during_dispatch = nil
    framework_lifecycle = nil
    lifecycle_probe = nil
    RequestLifecycleProbe.before_request
    queue_above_threshold = nil
    callback_targets = ListController._process_action_callbacks.map(&:filter).select { |filter| filter.is_a?(Symbol) }
    callback_events = []
    middleware_classes = Rails.application.middleware.map(&:klass)
    middleware_events = []
    trace = TracePoint.new(:call, :return) do |event|
      if event.event == :call && event.method_id == :complete && event.self.equal?(ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks)
        RequestLifecycleProbe.observe_pool_completion
      end
      if event.event == :call && event.method_id == :finalize_session && event.self.is_a?(ActiveRecord::AsynchronousQueriesTracker)
        Thread.current[:fidelity_pool_at_query_completion] = !!ActiveRecord::Base.connection_pool.active_connection?
      end
      if event.event == :call && event.method_id == :push && event.self.equal?(ActiveSupport::ExecutionContext)
        Thread.current[:fidelity_context_entry_interlock_depth] = RequestLifecycleProbe.interlock_depth
      end
      if event.event == :return && [:overloaded?, :overloaded_for_latest_json?].include?(event.method_id) && event.path.end_with?("/lib/middleware/overload_protections.rb")
        queue_above_threshold = event.return_value
      end
      if [:call, :call!].include?(event.method_id)
        middleware = middleware_classes.find { |klass| event.self.class == klass } || middleware_classes.find { |klass| event.self.is_a?(klass) }
        if middleware
          path = event.path
          path = path.delete_prefix(File.expand_path(".") + "/") if path.start_with?(File.expand_path(".") + "/")
          middleware_events << {phase: event.event, middleware: middleware.name, owner: event.defined_class.name,
            source: path, line: event.lineno}
        end
      end
      if callback_targets.include?(event.method_id) && event.path.start_with?(File.expand_path(".") + "/")
        callback_events << {phase: event.event, method: event.method_id,
          source: event.path.delete_prefix(File.expand_path(".") + "/"), line: event.lineno}
      end
      if event.event == :return && event.method_id == :set_crawler_header
        callback_locale = I18n.locale.to_s
      end
      if event.event == :return && event.method_id == :check_readonly_mode
        readonly_state = LatestLayoutProbe.readonly_state(event.self)
      end
      if event.event == :return && event.method_id == :set_mp_snapshot_fields
        snapshot_fields = Rack::MiniProfiler.get_snapshot_custom_fields&.dup
      end
      if event.event == :return && event.method_id == :initialize_application_layout_preloader
        layout_state = LatestLayoutProbe.capture(event.self)
      end
      if event.event == :call && event.path.end_with?("/app/controllers/application_controller.rb") && event.method_id == :ensure_dont_cache_page
        processing_seen = Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY]
        request_id_during_dispatch = event.self.request.request_id
        cors_origins_during_dispatch = event.self.request.env[Discourse::Cors::ORIGINS_ENV]
        authorized_host_during_dispatch = event.self.request.env["action_dispatch.authorized_host"]
        remote_ip_during_dispatch = {value: event.self.request.remote_ip,
          lazy_class: event.self.request.env["action_dispatch.remote_ip"].class.name}
        lifecycle_probe = RequestLifecycleProbe.new
        connection = ActiveRecord::Base.connection_pool.active_connection?
        framework_lifecycle = {executor_active_during_controller: Rails.application.executor.active?,
          reloader_active_during_controller: Rails.application.reloader.active?,
          executor_run_callbacks: lifecycle_callbacks(Rails.application.executor, :run),
          executor_complete_callbacks: lifecycle_callbacks(Rails.application.executor, :complete),
          action_dispatch_callbacks: lifecycle_callbacks(ActionDispatch::Callbacks, :call),
          active_connection_during_controller: !!connection,
          query_cache_enabled_during_controller: !!ActiveRecord::Base.connection_pool.query_cache_enabled,
          context_and_queries_during_controller: lifecycle_probe.during_controller}
      end
      next unless event.event == :call && event.path.end_with?("/mini_profiler/storage/redis_store.rb") && event.method_id == :save
      page = event.binding.local_variable_get(:page_struct)
      current_id = page[:id]
      processing_during_save = Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY]
    end
    begin
      trace.enable
      response = yield
    ensure
      trace.disable
    end
    if response.status == 503
      raise "overload entered profiler/controller" unless current_id.nil? && callback_events.empty?
      effects = {controller_dispatched: !callback_events.empty?, profiler_saved: !current_id.nil?,
        processing_after_dispatch: Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY],
        queue_above_threshold: queue_above_threshold}
      return [response, nil, effects]
    end
    config = Rack::MiniProfiler.config
    store = config.storage_instance
    raise "not real original RedisStore" unless store.is_a?(Rack::MiniProfiler::RedisStore)
    raise "original profiler did not save a page" unless current_id
    current = store.load(current_id)
    raise "original profiler page missing after save" unless current && current[:id] == current_id
    user = config.user_provider.call(env)
    unviewed = store.get_unviewed_ids(user)
    headers = response.headers.to_h.transform_keys(&:downcase)
    ids = headers["x-miniprofiler-ids"]&.split(",") || []
    if response.status >= 200 && response.status < 300
      expected = ([current_id] + unviewed).uniq.first(config.max_traces_to_show)
      raise "original header lost real store order" unless ids == expected
    else
      raise "error response advertised profiler IDs" unless ids.empty?
    end
    if framework_lifecycle
      framework_lifecycle[:context_and_queries_after_response] = lifecycle_probe.after_response
      framework_lifecycle[:executor_active_after_response_close] = Rails.application.executor.active?
      framework_lifecycle[:reloader_active_after_response_close] = Rails.application.reloader.active?
    end
    proof = {current_id: current_id, original_callback_events: callback_events,
      original_framework_lifecycle_contracts: framework_lifecycle,
      original_declared_middleware_stack: middleware_classes.map(&:name), original_middleware_events: middleware_events,
      ordered_unviewed_ids: unviewed,
      max_traces_to_show: config.max_traces_to_show,
      stored_pages: ([current_id] + ids).uniq.map do |id|
        page = store.load(id)
        raise "advertised profiler record missing" unless page && page[:id] == id
        {id: page[:id], request_method: page[:request_method], request_path: page[:request_path],
         user: page[:user], fields: page.attributes.keys.map(&:to_s).sort,
         sql_count: page[:sql_count], root_name: page[:root][:name]}
      end}
    effects = {processing_during_dispatch: processing_seen,
      processing_during_profiler_save: processing_during_save,
      processing_after_dispatch: Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY],
      profiler_authorized_after_dispatch: Rack::MiniProfiler.request_authorized?,
      application_layout_preloader: layout_state,
      profiler_snapshot_fields: snapshot_fields,
      readonly_state: readonly_state,
      request_locale: {during_callbacks: callback_locale, after_dispatch: I18n.locale.to_s},
      cors_origins_during_dispatch: cors_origins_during_dispatch,
      authorized_host_during_dispatch: authorized_host_during_dispatch,
      remote_ip_during_dispatch: remote_ip_during_dispatch,
      request_id_visible_and_consistent: !request_id_during_dispatch.nil? && request_id_during_dispatch == headers["x-request-id"]}
    [response, proof, effects]
  end
end
