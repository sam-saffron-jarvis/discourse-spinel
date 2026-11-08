# frozen_string_literal: true
module ActiveRecord
  # Ownership token for the backend's request query cache. Mirrors the
  # run/complete contract of Rails QueryCache::ExecutorHooks: only a scope
  # which enabled caching disables/clears it. An enclosing cache survives.
  # This is NOT the rest of Rails' executor hook registry or a DB lease.
  class QueryCacheScope
    def initialize
      @owned = !Db.query_cache_enabled?
      @completed = false
      Db.query_cache_begin if @owned
    end

    def complete!
      return nil if @completed
      @completed = true
      Db.query_cache_end if @owned
      nil
    end
  end

  # Eager Array[String] response-body boundary. The body is already rendered,
  # but completion belongs to close, not to the middleware's return. Like
  # Rack::BodyProxy, repeated close cannot complete a later request's scope.
  # Streaming/user-defined closeable bodies are a separate unsupported API.
  class QueryCacheScopeBody
    def initialize(body, scope)
      @body = body
      @scope = scope
      @closed = false
    end

    def join(separator = "")
      @body.join(separator)
    end

    def close
      return nil if @closed
      @closed = true
      @scope.complete!
      nil
    end

    def closed?
      @closed
    end
  end
end
