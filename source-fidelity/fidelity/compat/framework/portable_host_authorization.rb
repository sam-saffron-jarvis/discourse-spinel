# frozen_string_literal: true
# GENERATED actual Rails/Discourse development host classifier and scope.
# Blocked-host debug HTML/custom response applications explicitly refuse.
require "ipaddr"
module ActionDispatch
  class HostAuthorization
    ALLOWED_HOSTS_IN_DEVELOPMENT = [".localhost", ".test", IPAddr.new("0.0.0.0/0"), IPAddr.new("::/0")]
PORT_REGEX = /(?::\d+)/
SUBDOMAIN_REGEX = /(?:[a-z0-9-]+\.)/i
IPV4_HOSTNAME = /(?<host>\d+\.\d+\.\d+\.\d+)#{PORT_REGEX}?/
IPV6_HOSTNAME = /(?<host>[a-f0-9]*:[a-f0-9.:]+)/i
IPV6_HOSTNAME_WITH_PORT = /\[#{IPV6_HOSTNAME}\]#{PORT_REGEX}/i
VALID_IP_HOSTNAME = Regexp.union( # :nodoc:
      /\A#{IPV4_HOSTNAME}\z/,
      /\A#{IPV6_HOSTNAME}\z/,
      /\A#{IPV6_HOSTNAME_WITH_PORT}\z/,
    )
    class Permissions # :nodoc:
      def initialize(hosts)
        @hosts = sanitize_hosts(hosts)
      end

      def empty?
        @hosts.empty?
      end

      def allows?(host)
        @hosts.any? do |allowed|
          if allowed.is_a?(IPAddr)
            begin
              allowed === extract_hostname(host)
            rescue
              # IPAddr#=== raises an error if you give it a hostname instead of IP. Treat
              # similar errors as blocked access.
              false
            end
          else
            allowed === host
          end
        end
      end

      private
        def sanitize_hosts(hosts)
          Array(hosts).map do |host|
            case host
            when Regexp then sanitize_regexp(host)
            when String then sanitize_string(host)
            else host
            end
          end
        end

        def sanitize_regexp(host)
          /\A#{host}#{PORT_REGEX}?\z/
        end

        def sanitize_string(host)
          port = "#{PORT_REGEX}?" unless host.match?(/:\d+\z/)
          if host.start_with?(".")
            /\A#{SUBDOMAIN_REGEX}?#{Regexp.escape(host[1..-1])}#{port}\z/i
          else
            /\A#{Regexp.escape host}#{port}\z/i
          end
        end

        def extract_hostname(host)
          host.slice(VALID_IP_HOSTNAME, "host") || host
        end
    end
    def initialize(app, hosts, exclude: nil, response_app: nil)
      @app = app
      @permissions = Permissions.new(hosts)
      @exclude = exclude

      raise ArgumentError, "unsupported custom host response app profile" unless response_app.nil?
    end

def call(env)
      return @app.call(env) if @permissions.empty?

      request = Rack::CoreRequest.new(env)
      hosts = blocked_hosts(request)

      if hosts.empty? || excluded?(request)
        mark_as_authorized(request)
        @app.call(env)
      else
        env["action_dispatch.blocked_hosts"] = hosts
        raise ArgumentError, "unsupported blocked-host JSON request profile"
      end
    end

def blocked_hosts(request)
        hosts = []

        origin_host = request.get_header("HTTP_HOST")
        hosts << origin_host unless @permissions.allows?(origin_host)

        forwarded_host = request.x_forwarded_host&.split(/,\s?/)&.last
        hosts << forwarded_host unless PortableResponseMiddlewareDeclarations.blank_header?(forwarded_host) || @permissions.allows?(forwarded_host)

        hosts
      end

def excluded?(request)
        @exclude && @exclude.call(request)
      end

def mark_as_authorized(request)
        request.set_header("action_dispatch.authorized_host", request.host)
      end
  end
end
module PortableHostAuthorizationDeclarations
  def self.hosts
    raise ArgumentError, "unsupported non-development host authorization profile" unless ENV.fetch("RAILS_ENV") == "development"
    # The deprecated option also emits a real deprecation event at boot.
    # Do not silently omit that event or pretend this profile handles it.
    raise ArgumentError, "unsupported deprecated development host configuration" unless ENV["DISCOURSE_DEV_HOSTS"].nil?
    hosts = ActionDispatch::HostAuthorization::ALLOWED_HOSTS_IN_DEVELOPMENT +
            ENV["RAILS_DEVELOPMENT_HOSTS"].to_s.split(",").map(&:strip)
    hosts << /\A(([a-z0-9-]+)\.)*localhost(\:\d+)?\Z/
    hosts
  end
end
