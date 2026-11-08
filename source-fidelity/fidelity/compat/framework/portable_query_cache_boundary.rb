# frozen_string_literal: true
# Real context, query-cache and synchronous query-session lifecycle.
# Includes running interlock and single-backend pool completion; completion
# belongs to close. NOT the generic/reloading executor or streaming protocol.
class PortableQueryCacheBoundary
  def initialize(app)
    @app = app
  end

  def new_scope
    ActiveRecord::RequestQueryScope.new
  end

  def call(env)
    scope = new_scope
    begin
      status, headers, body = @app.call(env)
      [status, headers, ActiveRecord::QueryCacheScopeBody.new(body, scope)]
    rescue Exception
      scope.complete!
      raise
    end
  end
end
