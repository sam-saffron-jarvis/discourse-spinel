# frozen_string_literal: true
require_relative "../active_support_reporters"
require_relative "../active_support_interlock"
require_relative "query_cache_scope"
require_relative "asynchronous_queries_tracker"
require_relative "connection_pool_executor"
module ActiveRecord
  # The context/query-cache/query-session portion of the Rails executor's
  # synchronous request lifecycle, including its outer running interlock.
  # Includes completion of the single configured backend's facade lease.
  # NOT Rails' reloading/upgrade protocol or full generic executor registry.
  # A QueryCacheScope subtype so the existing eager body-close boundary can
  # own the composite; no streaming/server or generic executor registry claim.
  class RequestQueryScope < QueryCacheScope
    def self.active?
      !Thread.current[:active_record_request_query_scope].nil?
    end

    def initialize
      @owns_execution = !RequestQueryScope.active?
      @completed = false
      @interlock_running = false
      @cache = nil
      @tracker = nil
      return unless @owns_execution
      Thread.current[:active_record_request_query_scope] = self
      begin
        start_interlock
        start_context
        @cache = QueryCacheScope.new
        start_queries
        start_connections
      rescue Exception
        complete!
        raise
      end
    end

    def start_interlock
      ActiveSupport::Dependencies.interlock.start_running
      @interlock_running = true
      nil
    end

    def finish_interlock
      if @interlock_running
        ActiveSupport::Dependencies.interlock.done_running
        @interlock_running = false
      end
      nil
    end

    def start_connections
      ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.run
      nil
    end

    def finish_connections
      ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.complete(nil)
      nil
    end

    def start_context
      ActiveSupport::ExecutionContext.push
      nil
    end

    def start_queries
      @tracker = AsynchronousQueriesTracker.run
      nil
    end

    def finish_context
      ActiveSupport::CurrentAttributes.clear_all
      ActiveSupport::ExecutionContext.pop
      ActiveSupport.event_reporter.clear_context
      nil
    end

    def finish_queries
      tracker = @tracker
      AsynchronousQueriesTracker.complete(tracker) unless tracker.nil?
      nil
    end

    def complete!
      return nil if @completed
      @completed = true
      return nil unless @owns_execution
      begin
        # Original complete callbacks are FIFO, not reverse run order.
        finish_context
        cache = @cache
        cache.complete! unless cache.nil?
        finish_queries
        finish_connections
        finish_interlock
      ensure
        Thread.current[:active_record_request_query_scope] = nil
      end
      nil
    end
  end
end
