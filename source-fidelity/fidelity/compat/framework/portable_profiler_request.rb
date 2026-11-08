# frozen_string_literal: true
require "cgi"
# Env-backed Rack request adapter used by the shared profiler, not a controller
# replacement. Cookie duplicate/decoding semantics follow Rack2. The initial
# profiler middleware refuses forwarded/proxy profiles before using this IP/SSL
# subset; the actual controller still receives ActionDispatch::Request.
module Rack
  class CoreRequest
    attr_reader :env

    def remote_addr
      get_header("REMOTE_ADDR")
    end

    def client_ip
      get_header("HTTP_CLIENT_IP")
    end

    def x_forwarded_for
      get_header("HTTP_X_FORWARDED_FOR")
    end

    # Only the declared direct-peer profile reaches this adapter. Never
    # silently ignore forwarding input when used outside the dispatcher.
    def forwarded_for
      if @env.key?("HTTP_FORWARDED") || @env.key?("HTTP_X_FORWARDED_FOR") || @env.key?("HTTP_CLIENT_IP")
        raise ArgumentError, "unsupported forwarded remote-IP adapter profile"
      end
      []
    end

    def remote_ip=(value)
      set_header("action_dispatch.remote_ip", value)
    end

    def initialize(env)
      @env = env
    end

    def get_header(name)
      @env.fetch(name, nil)
    end

    def set_header(name, value)
      @env[name] = value
    end

    def x_forwarded_host
      get_header("HTTP_X_FORWARDED_HOST")
    end

    # ActionDispatch::Http::URL's source host algorithm. HostAuthorization
    # writes into this SAME environment, not a cloned Request context.
    def host
      forwarded = x_forwarded_host
      authority = if !PortableResponseMiddlewareDeclarations.blank_header?(forwarded)
        forwarded.to_s.split(/,\s?/).last
      else
        get_header("HTTP_HOST") || "#{get_header('SERVER_NAME')}:#{get_header('SERVER_PORT')}"
      end
      raise ArgumentError, "unsupported missing host authority profile" if authority.nil?
      authority.to_s.sub(/:\d+$/, "")
    end

    def cookies
      header = @env["HTTP_COOKIE"]
      return {} if header.nil?
      cookies = {}
      header.split(/[;] */n).each do |cookie|
        next if cookie.empty?
        key, value = cookie.split("=", 2)
        unless cookies.key?(key)
          cookies[key] = begin
            CGI.unescape(value)
          rescue
            value
          end
        end
      end
      cookies
    end

    def ip
      @env["REMOTE_ADDR"]
    end

    def ssl?
      @env["HTTPS"] == "on" || @env["rack.url_scheme"] == "https"
    end
  end
end
