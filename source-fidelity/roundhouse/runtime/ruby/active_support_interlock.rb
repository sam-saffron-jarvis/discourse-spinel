# frozen_string_literal: true
module ActiveSupport
  module Dependencies
    # The running/unloading share/exclusive interlock. Synchronous request readers
    # are real lock holders: an unloader waits for their last release, and fresh
    # readers wait behind an unloader. Reentrant readers/writers keep ownership.
    # Share-to-exclusive upgrades and Rails' compatible yield_shares protocol are
    # explicitly unsupported; the admitted no-reloading request never uses them.
    class RunningShare
      attr_reader :thread
      attr_accessor :depth
      def initialize(thread)
        @thread = thread
        @depth = 0
      end
    end

    class Interlock
      def initialize
        @mutex = Mutex.new
        @changed = ConditionVariable.new
        @sharing = empty_shares
        @exclusive_thread = nil
        @exclusive_depth = 0
        @waiting_writers = 0
      end

      def empty_shares
        []
      end

      def running_depth
        @mutex.synchronize do
          share = @sharing.find { |entry| entry.thread == Thread.current }
          share.nil? ? 0 : share.depth
        end
      end

      def start_running
        @mutex.synchronize do
          thread = Thread.current
          share = @sharing.find { |entry| entry.thread == thread }
          depth = share.nil? ? 0 : share.depth
          if depth == 0 && @exclusive_thread != thread
            @changed.wait(@mutex) while !@exclusive_thread.nil? || @waiting_writers > 0
          end
          if share.nil?
            share = RunningShare.new(thread)
            @sharing << share
          end
          share.depth = depth + 1
        end
      end

      def done_running
        @mutex.synchronize do
          thread = Thread.current
          share = @sharing.find { |entry| entry.thread == thread }
          unless share.nil?
            if share.depth > 1
              share.depth -= 1
            else
              @sharing.delete(share)
              @changed.broadcast
            end
          end
        end
        nil
      end

      def start_unloading
        @mutex.synchronize do
          thread = Thread.current
          if @exclusive_thread == thread
            @exclusive_depth += 1
          else
            raise NotImplementedError, "interlock share-to-exclusive upgrade/yield_shares profile is unsupported" if @sharing.any? { |entry| entry.thread == thread }
            @waiting_writers += 1
            begin
              @changed.wait(@mutex) while !@exclusive_thread.nil? || !@sharing.empty?
              @exclusive_thread = thread
              @exclusive_depth = 1
            ensure
              @waiting_writers -= 1
            end
          end
        end
        true
      end

      def done_unloading
        @mutex.synchronize do
          raise "invalid unlock" unless @exclusive_thread == Thread.current
          @exclusive_depth -= 1
          if @exclusive_depth == 0
            @exclusive_thread = nil
            @changed.broadcast
          end
        end
        nil
      end
    end

    INTERLOCK = Interlock.new
    def self.interlock
      INTERLOCK
    end
  end
end
