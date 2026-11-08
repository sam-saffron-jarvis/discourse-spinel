# frozen_string_literal: true
module ActiveRecord
  # active_record/asynchronous_queries_tracker.rb, without concurrent-ruby's
  # AtomicBoolean/ReadWriteLock dependency. The mutex protects the active flag
  # and the real reader count; a waiting finalizer excludes new readers until
  # existing readers finish. No query execution/background worker is invented.
  class AsynchronousQueriesTracker
    class Session
      def initialize
        @active = true
        @mutex = Mutex.new
        @changed = ConditionVariable.new
        @readers = 0
        @finalizing = false
      end

      def active?
        @mutex.synchronize { @active }
      end

      def synchronize
        @mutex.synchronize do
          @changed.wait(@mutex) while @finalizing
          @readers += 1
        end
        begin
          yield
        ensure
          @mutex.synchronize do
            @readers -= 1
            @changed.broadcast if @readers == 0
          end
        end
      end

      def finalize(wait = false)
        @mutex.synchronize do
          @active = false
          if wait
            @changed.wait(@mutex) while @finalizing
            @finalizing = true
            begin
              @changed.wait(@mutex) while @readers > 0
            ensure
              @finalizing = false
              @changed.broadcast
            end
          end
        end
        nil
      end
    end

    def self.run
      tracker = Base.asynchronous_queries_tracker
      tracker.start_session
      tracker
    end

    def self.complete(tracker)
      tracker.finalize_session
    end

    def empty_sessions
      []
    end

    def initialize
      @stack = empty_sessions
    end

    def current_session
      session = @stack.last
      raise ActiveRecordError, "Can't perform asynchronous queries without a query session" if session.nil?
      session
    end

    def start_session
      session = Session.new
      @stack << session
    end

    def finalize_session(wait = false)
      unless @stack.empty?
        session = current_session
        @stack.pop
        session.finalize(wait)
      end
      self
    end
  end

  class Base
    def self.asynchronous_queries_tracker
      current = Thread.current[:active_record_asynchronous_queries_tracker]
      return current unless current.nil?
      tracker = AsynchronousQueriesTracker.new
      Thread.current[:active_record_asynchronous_queries_tracker] = tracker
      tracker
    end
  end
end
