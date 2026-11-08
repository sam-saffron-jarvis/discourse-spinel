# frozen_string_literal: true
# Transport-free, in-process controller dispatch for the Ruby-family runtime.
# Uses the same Request, generated process_action, Current context and response
# finalizers as the HTTP dispatcher. No socket/server/job implementation loads.
# The initial surface is explicitly GET/HEAD with an empty incoming cookie jar;
# other transports/session profiles refuse instead of pretending to run them.
require_relative "action_dispatch/request_id"

module ActionDispatch
  # Ruby-family binding of Actionpack8.1 RequestId#call's actual Rack boundary.
  # Request#get_header/set_header/request_id share this env slot. Access it
  # directly rather than constructing a second accessor-backed Request.
  class RequestIdMiddleware
    ENV_REQUEST_ID = "action_dispatch.request_id"

    def initialize(app, header: RequestId::HEADER)
      @app = app
      @header = header
      @env_header = "HTTP_#{header.upcase.tr('-', '_')}"
    end

    def call(env)
      env[ENV_REQUEST_ID] = make_request_id(env.fetch(@env_header, nil).to_s)
      status, headers, body = @app.call(env)
      headers[@header] = env[ENV_REQUEST_ID]
      [status, headers, body]
    end

    def make_request_id(value)
      RequestId.make(value)
    end
  end

  module InProcessController
    def self.dispatch(controller, request, matched, etag_middleware: true, request_id_middleware: true)
      unless request.request_method == "GET" || request.request_method == "HEAD"
        raise ArgumentError, "unsupported in-process controller verb"
      end
      cookie = request.env["HTTP_COOKIE"]
      raise ArgumentError, "unsupported in-process cookie context" unless cookie.nil? || cookie == ""
      controller.request = request
      controller.params = request.params
      controller.path_parameters = matched.path_params
      controller.request_method = request.request_method
      controller.request_path = request.path
      controller.query_string = request.query_string
      controller.request_format = request.format.to_sym
      controller.vary_on_accept = false
      controller.cookies = ActionController::CookieJar.new({})
      previous_request = ActionController::Current.request
      previous_controller = ActionController::Current.controller
      begin
        ActionController::Current.request = request
        ActionController::Current.controller = controller
        controller.process_action(matched.action)
        controller.commit_cache_control!
        controller.commit_conditional_get!(request.request_method, request.env["HTTP_IF_NONE_MATCH"].to_s, etag_middleware: etag_middleware)
        controller.commit_default_headers!
        if request_id_middleware
          controller.headers[ActionDispatch::RequestId::HEADER] = ActionDispatch::RequestId.make(request.env["HTTP_X_REQUEST_ID"].to_s)
        end
        controller.headers["Content-Type"] = controller.content_type unless controller.content_type.empty?
        controller.headers["Content-Length"] = controller.body.bytesize.to_s
        controller.response
      ensure
        ActionController::Current.request = previous_request
        ActionController::Current.controller = previous_controller
      end
    end
  end
end
