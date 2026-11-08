# frozen_string_literal: true
# TEST-only real state/effect observers, shared verbatim by Rails and candidate.
# These objects are not profiler/query results or runtime application inputs.
class LifecycleProbeCurrent < ActiveSupport::CurrentAttributes
  attr_accessor :marker
  def reset
    @marker = nil
  end
end
class OtherLifecycleProbeCurrent < ActiveSupport::CurrentAttributes
  attr_accessor :marker
  def reset
    @marker = nil
  end
end
class RequestLifecycleProbe
  def self.interlock_depth
    ActiveSupport::Dependencies.interlock.running_depth
  end

  def self.before_request
    Thread.current[:fidelity_context_entry_interlock_depth] = nil
    Thread.current[:fidelity_pool_at_query_completion] = nil
    Thread.current[:fidelity_queries_completed_before_pool] = nil
    ActiveSupport::ExecutionContext[:fidelity_ambient] = "ambient"
    ActiveSupport.event_reporter.set_context({fidelity_ambient: "ambient"})
  end

  def self.observe_pool_completion
    return unless Thread.current[:fidelity_queries_completed_before_pool].nil?
    completed = false
    begin
      ActiveRecord::Base.asynchronous_queries_tracker.current_session
    rescue ActiveRecord::ActiveRecordError
      completed = true
    end
    Thread.current[:fidelity_queries_completed_before_pool] = completed
    nil
  end

  def initialize
    @entry_context = ActiveSupport::ExecutionContext.to_h
    @first = LifecycleProbeCurrent.new
    @first.marker = "first"
    @second = OtherLifecycleProbeCurrent.new
    @second.marker = "second"
    instances = ActiveSupport::ExecutionContext.current_attributes_instances
    instances[:LifecycleProbeCurrent] = @first
    instances[:OtherLifecycleProbeCurrent] = @second
    @session = nil
    begin
      @session = ActiveRecord::Base.asynchronous_queries_tracker.current_session
    rescue ActiveRecord::ActiveRecordError
      # Omitted-hook NEGATIVE must still produce a real successful response;
      # record the actual absent session, never synthesize one for the caller.
    end
    ActiveSupport::ExecutionContext[:fidelity_controller] = "controller"
    ActiveSupport.event_reporter.set_context({fidelity_controller: "controller"})
  end

  def during_controller
    session = @session
    {ambient_context_absent: !@entry_context.key?(:fidelity_ambient),
      query_session_active: !session.nil? && session.active?,
      active_connection_during_controller: !!ActiveRecord::Base.connection_pool.active_connection?,
      single_configured_pool: ActiveRecord::Base.connection_handler.connection_pool_list.size == 1,
      interlock_owned_during_controller: RequestLifecycleProbe.interlock_depth > 0,
      interlock_owned_at_context_push: (Thread.current[:fidelity_context_entry_interlock_depth] || 0) > 0}
  end

  def after_response
    instances = ActiveSupport::ExecutionContext.current_attributes_instances
    context = ActiveSupport::ExecutionContext.to_h
    events = ActiveSupport.event_reporter.context
    session = @session
    no_session = false
    begin
      ActiveRecord::Base.asynchronous_queries_tracker.current_session
    rescue ActiveRecord::ActiveRecordError
      no_session = true
    end
    {held_instances_reset: @first.marker.nil? && @second.marker.nil?,
      registered_instances_removed: !instances.key?(:LifecycleProbeCurrent) && !instances.key?(:OtherLifecycleProbeCurrent),
      execution_context_popped: !context.key?(:fidelity_controller) && !context.key?(:fidelity_ambient),
      event_context_cleared: !events.key?(:fidelity_controller) && !events.key?(:fidelity_ambient),
      query_session_finalized: !session.nil? && !session.active?, query_session_released: no_session,
      connection_lease_released: !ActiveRecord::Base.connection_pool.active_connection?,
      pool_held_at_query_completion: Thread.current[:fidelity_pool_at_query_completion] == true,
      query_session_completed_before_pool: Thread.current[:fidelity_queries_completed_before_pool] == true,
      interlock_released: RequestLifecycleProbe.interlock_depth == 0}
  end
end
