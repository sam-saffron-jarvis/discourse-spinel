# frozen_string_literal: true
require_relative "portable_profiler_request"
# GENERATED original profiler5 core components; not full debug/HTML/profile API acceptance.
require "json"
require "digest"
require "cgi"
require "securerandom"
module Rack
class MiniProfiler
def self.generate_id
  alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
  out = +""
  i = 0
  while i < 20
    digit = rand(36)
    out << alphabet[digit] unless out.empty? && digit == 0
    i += 1
  end
  out.empty? ? "0" : out
end
module TimerStruct
class Base

def initialize(attrs = {})
          @attributes = attrs
        end

def attributes
          @attributes ||= {}
        end

def [](name)
          attributes[name]
        end

def []=(name, val)
          attributes[name] = val
        end

def to_json(*a)
          # this does could take in an option hash, but the only interesting there is max_nesting.
          #   if this becomes an option we could increase
          ::JSON.generate(@attributes, max_nesting: 100)
        end
end
class Page < Base

def initialize(env)
          timer_id     = MiniProfiler.generate_id
          started_at   = (Time.now.to_f * 1000).to_i
          started      = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
          machine_name = env['SERVER_NAME']
          super(
            id: timer_id,
            name: page_name(env),
            started: started,
            started_at: started_at,
            machine_name: machine_name,
            level: 0,
            user: "unknown user",
            has_user_viewed: false,
            client_timings: nil,
            duration_milliseconds: 0,
            has_trivial_timings: true,
            has_all_trivial_timings: false,
            trivial_duration_threshold_milliseconds: 2,
            head: nil,
            sql_count: 0,
            cached_sql_count: 0,
            duration_milliseconds_in_sql: 0,
            has_sql_timings: true,
            has_duplicate_sql_timings: false,
            executed_readers: 0,
            executed_scalars: 0,
            executed_non_queries: 0,
            custom_timing_names: [],
            custom_timing_stats: {},
            custom_fields: {},
            has_flamegraph: false,
            flamegraph: nil
          )
          self[:request_method] = env['REQUEST_METHOD']
          self[:request_path] = env['PATH_INFO']
          name = "#{env['REQUEST_METHOD']} http://#{env['SERVER_NAME']}:#{env['SERVER_PORT']}#{env['SCRIPT_NAME']}#{page_name(env)}"
          self[:root] = TimerStruct::Request.createRoot(name, self)
        end

def page_name(env)
          if env['QUERY_STRING'] && env['QUERY_STRING'] != ""
            env['PATH_INFO'] + "?" + env['QUERY_STRING']
          else
            env['PATH_INFO']
          end
        end

def root
          @attributes[:root]
        end

def duration_ms
          @attributes[:root][:duration_milliseconds]
        end

def attributes_to_serialize
          @attributes.keys - [:flamegraph]
        end

def to_json(*a)
          ::JSON.generate(@attributes.slice(*attributes_to_serialize).merge(extra_json))
        end

def extra_json
          {
            started_formatted: '/Date(%d)/' % @attributes[:started_at],
            duration_milliseconds: @attributes[:root][:duration_milliseconds],
            custom_timing_names: @attributes[:custom_timing_stats].keys.sort
          }
        end
end
class Request < Base
attr_accessor :children_duration, :start, :parent
def self.createRoot(name, page)
          TimerStruct::Request.new(name, page, nil).tap do |timer|
            timer[:is_root] = true
          end
        end

def initialize(name, page, parent)
          start_millis = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - page[:started]
          depth        = parent ? parent.depth + 1 : 0
          super(
            id: MiniProfiler.generate_id,
            name: name,
            duration_milliseconds: 0,
            duration_without_children_milliseconds: 0,
            start_milliseconds: start_millis,
            parent_timing_id: nil,
            children: [],
            has_children: false,
            key_values: nil,
            has_sql_timings: false,
            has_duplicate_sql_timings: false,
            trivial_duration_threshold_milliseconds: 2,
            sql_timings: [],
            sql_timings_duration_milliseconds: 0,
            is_trivial: false,
            is_root: false,
            depth: depth,
            executed_readers: 0,
            executed_scalars: 0,
            executed_non_queries: 0,
            custom_timing_stats: {},
            custom_timings: {}
          )
          @children_duration = 0
          @start             = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @parent            = parent
          @page              = page
        end

def depth
          self[:depth]
        end

def record_time(milliseconds = nil)
          milliseconds ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start) * 1000
          self[:duration_milliseconds]                  = milliseconds
          self[:is_trivial]                             = true if milliseconds < self[:trivial_duration_threshold_milliseconds]
          self[:duration_without_children_milliseconds] = milliseconds - self[:children].sum(&:duration_ms)
        end

def duration_ms
          self[:duration_milliseconds]
        end

def add_child(name)
          TimerStruct::Request.new(name, @page, self).tap do |timer|
            self[:children].push(timer)
            self[:has_children]      = true
            timer[:parent_timing_id] = self[:id]
            timer[:depth]            = self[:depth] + 1
          end
        end

def add_sql(query, elapsed_ms, page, params = nil, skip_backtrace = false, full_backtrace = false, cached = false)
          TimerStruct::Sql.new(query, elapsed_ms, page, self, params, skip_backtrace, full_backtrace, cached).tap do |timer|
            self[:sql_timings].push(timer)
            timer[:parent_timing_id] = self[:id]
            self[:has_sql_timings]   = true
            self[:sql_timings_duration_milliseconds] += elapsed_ms
            page[:duration_milliseconds_in_sql]      += elapsed_ms
            page[:sql_count] += 1
            page[:cached_sql_count] += 1 if cached
          end
        end

def add_custom(type, elapsed_ms, page)
          TimerStruct::Custom.new(type, elapsed_ms, page, self).tap do |timer|
            timer[:parent_timing_id] = self[:id]

            self[:custom_timings][type] ||= []
            self[:custom_timings][type].push(timer)

            self[:custom_timing_stats][type] ||= { count: 0, duration: 0.0 }
            self[:custom_timing_stats][type][:count]    += 1
            self[:custom_timing_stats][type][:duration] += elapsed_ms

            page[:custom_timing_stats][type] ||= { count: 0, duration: 0.0 }
            page[:custom_timing_stats][type][:count]    += 1
            page[:custom_timing_stats][type][:duration] += elapsed_ms
          end
        end
end
class Sql < Base
attr_accessor :parent
def initialize(query, duration_ms, page, parent, params = nil, skip_backtrace = false, full_backtrace = false, cached = false)

          stack_trace = nil
          unless skip_backtrace || duration_ms < Rack::MiniProfiler.config.backtrace_threshold_ms
            # Allow us to filter the stack trace
            stack_trace = "".dup
            # Clean up the stack trace if there are options to do so
            Kernel.caller.each do |ln|
              ln.gsub!(Rack::MiniProfiler.config.backtrace_remove, '') if Rack::MiniProfiler.config.backtrace_remove && !full_backtrace
              if    full_backtrace ||
                    (
                      (
                        Rack::MiniProfiler.config.backtrace_includes.nil? ||
                        Rack::MiniProfiler.config.backtrace_includes.any? { |regex| ln =~ regex }
                      ) &&
                      (
                        Rack::MiniProfiler.config.backtrace_ignores.nil? ||
                        Rack::MiniProfiler.config.backtrace_ignores.none? { |regex| ln =~ regex }
                      )
                    )
                stack_trace << ln << "\n"
              end
            end
          end

          @parent      = parent
          @page        = page
          start_millis = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - page[:started]) - duration_ms
          super(
            execute_type: 3, # TODO
            formatted_command_string: query ? CGI.escapeHTML(query) : nil,
            stack_trace_snippet: stack_trace,
            start_milliseconds: start_millis,
            duration_milliseconds: duration_ms,
            first_fetch_duration_milliseconds: duration_ms,
            parameters: query ? trim_binds(params) : nil,
            row_count: 0,
            class_name: nil,
            parent_timing_id: nil,
            cached: cached,
            is_duplicate: false
          )
        end

def trim_binds(binds)
          max_len = Rack::MiniProfiler.config.max_sql_param_length
          return if binds.nil? || max_len == 0
          return binds.map { |(name, val)| [name, val] } if max_len.nil?
          binds.map do |(name, val)|
            val ||= name
            if val.nil? || val == true || val == false || val.kind_of?(Numeric)
              # keep these parameters as is
            elsif val.kind_of?(String)
              val = val[0...max_len] + (max_len < val.length ? '...' : '') if max_len
            else
              val = val.class.name
            end
            if name.kind_of?(String)
              name = name[0...max_len] + (max_len < name.length ? '...' : '') if max_len
            end
            [name, val]
          end
        end

def report_reader_duration(elapsed_ms, row_count = nil, class_name = nil)
          return if @reported
          @reported = true
          self[:duration_milliseconds]                += elapsed_ms
          @parent[:sql_timings_duration_milliseconds] += elapsed_ms
          @page[:duration_milliseconds_in_sql]        += elapsed_ms
          self[:row_count] = self[:row_count].to_i + row_count if row_count
          self[:class_name] = class_name if class_name
        end
end
class Custom < Base
attr_accessor :parent
def initialize(type, duration_ms, page, parent)
          @parent      = parent
          @page        = page
          @type        = type
          start_millis = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - page[:started]) - duration_ms
          super(
            type: type,
            start_milliseconds: start_millis,
            duration_milliseconds: duration_ms,
            parent_timing_id: nil
          )
        end
end
end
class Context
  attr_accessor :inject_js, :current_timer, :page_struct, :skip_backtrace,
    :full_backtrace, :discard, :mpt_init, :measure
  def initialize(opts = {})
    raise ArgumentError, "unsupported profiler context options" unless opts.empty?
    @inject_js = nil
    @current_timer = nil
    @page_struct = nil
    @skip_backtrace = nil
    @full_backtrace = nil
    @discard = nil
    @mpt_init = nil
    @measure = true
  end
end
class Config
attr_accessor :auto_inject, :cookie_path, :disable_caching, :enabled, :authorization_mode, :max_traces_to_show, :max_sql_param_length, :backtrace_threshold_ms, :backtrace_remove, :backtrace_includes, :backtrace_ignores, :snapshots_transport_destination_url, :snapshots_transport_auth_key, :profile_parameter, :storage_instance, :base_url_path, :storage_failure, :logger, :pre_authorize_cb, :user_provider, :skip_paths, :suppress_encoding, :snapshot_every_n_requests, :position, :snapshots_redact_sql_queries
def initialize
@auto_inject      = true
@cookie_path      = "/".dup
@disable_caching  = true
@enabled = true
@authorization_mode     = :allow_all
@max_traces_to_show   = 20
@max_sql_param_length = 0
@backtrace_threshold_ms = 0
@backtrace_remove = nil
@backtrace_includes = nil
@backtrace_ignores = nil
@snapshots_transport_destination_url = nil
@snapshots_transport_auth_key = nil
@profile_parameter = "pp"
@storage_instance = nil
@base_url_path    = "/mini-profiler-resources/".dup
@storage_failure = Proc.new do |exception|
            if @logger
              @logger.warn("MiniProfiler storage failure: #{exception.message}")
            end
          end
@logger = nil
@pre_authorize_cb = lambda { |env| true }
@user_provider          = Proc.new { |env| Rack::Request.new(env).ip }
@skip_paths = nil
@suppress_encoding = nil
@snapshot_every_n_requests = -1
@position             = "top-left"
@snapshots_redact_sql_queries = true
end
def self.default
new
end
end
class << self
def config
        @config ||= Config.default
      end

def current
        Thread.current[:mini_profiler_private]
      end

def current=(c)
        # we use TLS cause we need access to this from sql blocks and code blocks that have no access to env
        Thread.current[:mini_profiler_snapshot_custom_fields] = nil
        Thread.current[:mp_ongoing_snapshot] = nil
        Thread.current[:mini_profiler_private] = c
      end

def create_current(env = {}, options = {})
        # profiling the request
        context               = Context.new
        context.inject_js     = config.auto_inject && (!env['HTTP_X_REQUESTED_WITH'].eql? 'XMLHttpRequest')
        context.page_struct   = TimerStruct::Page.new(env)
        context.current_timer = context.page_struct[:root]
        self.current          = context
      end

def authorize_request
        Thread.current[:mp_authorized] = true
      end

def deauthorize_request
        Thread.current[:mp_authorized] = nil
      end

def request_authorized?
        Thread.current[:mp_authorized]
      end

def add_snapshot_custom_field(key, value)
  fields = Thread.current[:mini_profiler_snapshot_custom_fields]
  if fields
    fields[key] = value
  else
    Thread.current[:mini_profiler_snapshot_custom_fields] = {key => value}
  end
  value
end

def get_snapshot_custom_fields
        Thread.current[:mini_profiler_snapshot_custom_fields]
      end

def snapshots_transporter?
        !!config.snapshots_transport_destination_url &&
        !!config.snapshots_transport_auth_key
      end

def redact_sql_queries?
        Thread.current[:mp_ongoing_snapshot] == true &&
        Rack::MiniProfiler.config.snapshots_redact_sql_queries
      end
def record_sql(query, elapsed_ms, params = nil, cached = nil)
        return unless current && current.current_timer
        c = current
        c.current_timer.add_sql(
          redact_sql_queries? ? nil : query,
          elapsed_ms,
          c.page_struct,
          redact_sql_queries? ? nil : params,
          c.skip_backtrace,
          c.full_backtrace,
          cached
        )
      end

def start_step(name)
        return unless current
        parent_timer          = current.current_timer
        current.current_timer = current_timer = current.current_timer.add_child(name)
        [current_timer, parent_timer]
      end

def finish_step(obj)
        return unless obj && current
        current_timer, parent_timer = obj
        current_timer.record_time
        current.current_timer = parent_timer
      end
end
def current
      MiniProfiler.current
    end
def current=(c)
      MiniProfiler.current = c
    end
def config
      @config
    end
def user(env)
      @config.user_provider.call(env)
    end
def ids(env)
      all = ([current.page_struct[:id]] + (@storage.get_unviewed_ids(user(env)) || [])).uniq
      if all.size > @config.max_traces_to_show
        all = all[0...@config.max_traces_to_show]
        @storage.set_all_unviewed(user(env), all)
      end
      all
    end
def ids_comma_separated(env)
      ids(env).join(",")
    end
def flamegraph_path(env)
      @config.base_url_path + 'flamegraph?id=' + current.page_struct[:id]
    end
def inject_profiler(env, status, headers, body)
      # mini profiler is meddling with stuff, we can not cache cause we will get incorrect data
      # Rack::ETag has already inserted some nonesense in the chain
      content_type = headers[Rack::CONTENT_TYPE]

      headers['x-miniprofiler-original-cache-control'] = headers[Rack::CACHE_CONTROL] unless headers[Rack::CACHE_CONTROL].nil?

      if config.disable_caching
        headers.delete(Rack::ETAG)
        headers.delete('date') || headers.delete('Date')
        headers[Rack::CACHE_CONTROL] = "no-store, must-revalidate, private, max-age=0"
      end

      # inject header
      if headers.is_a? Hash
        headers['x-miniprofiler-ids'] = ids_comma_separated(env)
        headers['x-miniprofiler-flamegraph-path'] = flamegraph_path(env) if current.page_struct[:has_flamegraph]
      end

      raise ArgumentError, "unsupported profiler HTML injection profile" if current.inject_js && content_type =~ /text\/html/; nil
    end
class AbstractStore
MAX_TOKEN_AGE = 1800
end
class RedisStore
EXPIRES_IN_SECONDS = 60 * 60 * 24
def initialize(args = nil)
        @args               = args || {}
        @prefix             = @args.delete(:prefix) || 'MPRedisStore'
        @redis_connection   = @args.delete(:connection)
        @expires_in_seconds = @args.delete(:expires_in) || EXPIRES_IN_SECONDS
      end

def save(page_struct)
        redis.setex prefixed_id(page_struct[:id]), @expires_in_seconds, Marshal::dump(page_struct)
      end

def load(id)
        key = prefixed_id(id)
        raw = redis.get key
        begin
          # rubocop:disable Security/MarshalLoad
          Marshal.load(raw) if raw
          # rubocop:enable Security/MarshalLoad
        rescue
          # bad format, junk old data
          redis.del key
          nil
        end
      end

def set_unviewed(user, id)
        key = user_key(user)
        if redis.call([:exists, prefixed_id(id)]) == 1
          expire_at = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i + redis.ttl(prefixed_id(id))
          redis.zadd(key, expire_at, id)
        end
        redis.expire(key, @expires_in_seconds)
      end

def get_unviewed_ids(user)
        key = user_key(user)
        redis.zremrangebyscore(key, '-inf', Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i)
        redis.zrevrangebyscore(key, '+inf', '-inf')
      end

def set_all_unviewed(user, ids)
        key = user_key(user)
        redis.del(key)
        ids.each do |id|
          if redis.call([:exists, prefixed_id(id)]) == 1
            expire_at = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i + redis.ttl(prefixed_id(id))
            redis.zadd(key, expire_at, id)
          end
        end
        redis.expire(key, @expires_in_seconds)
      end

def allowed_tokens
        key1, key1_old, key2 = redis.mget("#{@prefix}-key1", "#{@prefix}-key1_old", "#{@prefix}-key2")

        if key1 && (key1.length == 32)
          return [key1, key2].compact
        end

        timeout = Rack::MiniProfiler::AbstractStore::MAX_TOKEN_AGE

        # TODO  this could be moved to lua to correct a concurrency flaw
        # it is not critical cause worse case some requests will miss profiling info

        # no key so go ahead and set it
        key1 = SecureRandom.hex

        if key1_old && (key1_old.length == 32)
          key2 = key1_old
          redis.setex "#{@prefix}-key2", timeout, key2
        else
          key2 = nil
        end

        redis.setex "#{@prefix}-key1", timeout, key1
        redis.setex "#{@prefix}-key1_old", timeout * 2, key1

        [key1, key2].compact
      end

def prefixed_id(id)
        "#{@prefix}#{id}"
      end

def user_key(user)
        "#{@prefix}-#{user}-v1"
      end
def redis
raise ArgumentError, "profiler requires an explicitly injected Redis connection" if @redis_connection.nil?
@redis_connection
end
end
end
end
module Rack
CONTENT_TYPE      = 'Content-Type'
CACHE_CONTROL     = 'Cache-Control'
ETAG              = 'ETag'
SET_COOKIE        = 'Set-Cookie'
module Utils
class << self
def escape(s)
      CGI.escape(s.to_s)
    end

def add_cookie_to_header(header, key, value)
      case value
      when Hash
        domain  = "; domain=#{value[:domain]}"   if value[:domain]
        path    = "; path=#{value[:path]}"       if value[:path]
        max_age = "; max-age=#{value[:max_age]}" if value[:max_age]
        expires = "; expires=#{value[:expires].httpdate}" if value[:expires]
        secure = "; secure"  if value[:secure]
        httponly = "; HttpOnly" if (value.key?(:httponly) ? value[:httponly] : value[:http_only])
        same_site =
          case value[:same_site]
          when false, nil
            nil
          when :none, 'None', :None
            '; SameSite=None'
          when :lax, 'Lax', :Lax
            '; SameSite=Lax'
          when true, :strict, 'Strict', :Strict
            '; SameSite=Strict'
          else
            raise ArgumentError, "Invalid SameSite value: #{value[:same_site].inspect}"
          end
        value = value[:value]
      end
      value = [value] unless Array === value

      cookie = "#{escape(key)}=#{value.map { |v| escape v }.join('&')}#{domain}" \
        "#{path}#{max_age}#{expires}#{secure}#{httponly}#{same_site}"

      case header
      when nil, ''
        cookie
      when String
        [header, cookie].join("\n")
      when Array
        (header + [cookie]).join("\n")
      else
        raise ArgumentError, "Unrecognized cookie header value. Expected String, Array, or nil, got #{header.inspect}"
      end
    end

def set_cookie_header!(header, key, value)
      header[SET_COOKIE] = add_cookie_to_header(header[SET_COOKIE], key, value)
      nil
    end
def delete_cookie_header!(headers, key, value = {})
raise ArgumentError, "unsupported existing profiler cookie deletion"
end
end
end
end
# frozen_string_literal: true

module Rack
  class MiniProfiler
    class ClientSettings

      COOKIE_NAME = "__profilin"

      BACKTRACE_DEFAULT = nil
      BACKTRACE_FULL    = 1
      BACKTRACE_NONE    = 2

      attr_accessor :disable_profiling
      attr_accessor :backtrace_level

      def initialize(env, store, start)
        @request = ::Rack::CoreRequest.new(env)
        @cookie = @request.cookies[COOKIE_NAME]
        @store = store
        @start = start
        @backtrace_level = nil
        @orig_disable_profiling = @disable_profiling = nil

        @allowed_tokens, @orig_auth_tokens = nil

        if @cookie
          @cookie.split(",").map { |pair| pair.split("=") }.each do |k, v|
            @orig_disable_profiling = @disable_profiling = (v == 't') if k == "dp"
            @backtrace_level = v.to_i if k == "bt"
            @orig_auth_tokens = v.to_s.split("|") if k == "a"
          end
        end

        if !@backtrace_level.nil? && (@backtrace_level == 0 || @backtrace_level > BACKTRACE_NONE)
          @backtrace_level = nil
        end

        @orig_backtrace_level = @backtrace_level

      end

      def handle_cookie(result, preserve_cookie: false)
        status, headers, _body = result

        if (MiniProfiler.config.authorization_mode == :allow_authorized && !MiniProfiler.request_authorized?)
          # this is non-obvious, don't kill the profiling cookie on errors or short requests
          # this ensures that stuff that never reaches the rails stack does not kill profiling
          if !preserve_cookie && status.to_i >= 200 && status.to_i < 300 && ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start) > 0.1)
            discard_cookie!(headers)
          end
        else
          write!(headers)
        end

        result
      end

      def write!(headers)

        tokens_changed = false

        if MiniProfiler.request_authorized? && MiniProfiler.config.authorization_mode == :allow_authorized
          @allowed_tokens ||= @store.allowed_tokens
          tokens_changed = !@orig_auth_tokens || ((@allowed_tokens - @orig_auth_tokens).length > 0)
        end

        if  @orig_disable_profiling != @disable_profiling ||
            @orig_backtrace_level != @backtrace_level ||
            @cookie.nil? ||
            tokens_changed

          settings = { "p" => "t" }
          settings["dp"] = "t"                  if @disable_profiling
          settings["bt"] = @backtrace_level     if @backtrace_level
          settings["a"] = @allowed_tokens.join("|") if @allowed_tokens && MiniProfiler.request_authorized?
          settings_string = settings.map { |k, v| "#{k}=#{v}" }.join(",")
          cookie = { value: settings_string, path: MiniProfiler.config.cookie_path, httponly: true }
          cookie[:secure] = true if @request.ssl?
          cookie[:same_site] = 'Lax'
          Rack::Utils.set_cookie_header!(headers, COOKIE_NAME, cookie)
        end
      end

      def discard_cookie!(headers)
        if @cookie
          Rack::Utils.delete_cookie_header!(headers, COOKIE_NAME, path: MiniProfiler.config.cookie_path)
        end
      end

      def has_valid_cookie?
        valid_cookie = !@cookie.nil?

        if (MiniProfiler.config.authorization_mode == :allow_authorized) && valid_cookie
          begin
            @allowed_tokens ||= @store.allowed_tokens
          rescue => e
            if MiniProfiler.config.storage_failure != nil
              MiniProfiler.config.storage_failure.call(e)
            end
          end

          valid_cookie = @allowed_tokens &&
            (Array === @orig_auth_tokens) &&
            ((@allowed_tokens & @orig_auth_tokens).length > 0)
        end

        valid_cookie
      end

      def disable_profiling?
        @disable_profiling
      end

      def backtrace_full?
        @backtrace_level == BACKTRACE_FULL
      end

      def backtrace_default?
        @backtrace_level == BACKTRACE_DEFAULT
      end

      def backtrace_none?
        @backtrace_level == BACKTRACE_NONE
      end
    end
  end
end
