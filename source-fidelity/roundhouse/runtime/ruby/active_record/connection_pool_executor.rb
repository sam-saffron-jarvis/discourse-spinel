# frozen_string_literal: true
require_relative "../active_support_notifications"
module ActiveRecord
  # The AR facade lease is distinct from Db's physical checkout/transaction pin.
  # Returning this lease must never roll back or unpin an enclosing owner's
  # readonly fixture. The facade is stateless; the actual session is Db's holder.
  module ConnectionLease
    def self.checkout
      connection = Connection.shared
      Thread.current[:active_record_connection_lease] = connection
      connection
    end

    def self.current
      connection = Thread.current[:active_record_connection_lease]
      return connection if connection.is_a?(Connection)
      nil
    end

    def self.release
      Thread.current[:active_record_connection_lease] = nil
      nil
    end

    # Lowered model SQL goes directly through Db, not Base.connection. Bind its
    # real SQL usage to the same facade lease via the existing backend SQL event;
    # no query rows, fake SQL, fixture flags or executor activity inference.
    def self.install
      return nil if @installed
      @installed = true
      ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, _payload|
        checkout
        nil
      end
      nil
    end
  end

  module ConnectionAdapters
    class DbPool
      def active_connection?
        ConnectionLease.current
      end

      def release_connection
        ConnectionLease.release
      end

      def with_connection
        prior = active_connection?
        connection = ConnectionLease.checkout
        begin
          yield connection
        ensure
          release_connection if prior.nil?
        end
      end
    end

    class ConnectionPool
      module ExecutorHooks
        def self.run
          nil
        end

        def self.complete(state)
          _ = state
          Base.connection_handler.each_connection_pool do |pool|
            connection = pool.active_connection?
            unless connection.nil?
              transaction = connection.current_transaction
              if transaction.closed? || !transaction.joinable?
                pool.release_connection
              end
            end
          end
          nil
        end
      end
    end
  end

  # There is one real configured backend in this runtime. Additional database
  # configurations/multisite selection remain unsupported by request admission.
  class ConnectionHandler
    def connection_pool_list
      [Base.connection_pool]
    end

    def each_connection_pool
      connection_pool_list.each { |pool| yield pool }
      nil
    end
  end

  CONNECTION_POOL = ConnectionAdapters::DbPool.new
  CONNECTION_HANDLER = ConnectionHandler.new
  class Base
    def self.connection_pool
      CONNECTION_POOL
    end

    def self.connection_handler
      CONNECTION_HANDLER
    end
  end

  ConnectionLease.install
end
