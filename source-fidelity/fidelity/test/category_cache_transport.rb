# frozen_string_literal: true
# Platform transport binding for the original MessageBus Redis backend.
# NOT a new backend, fake Redis, alternate script or generic job dispatcher.
require_relative "owned_cache_policy"
module CategoryCacheOutput
  LOCK = Mutex.new
  def self.write(line); LOCK.synchronize { puts line }; end
  def self.synchronize; LOCK.synchronize { yield }; end
end
class CategoryCacheLease
  attr_reader :host, :port, :namespace, :events, :category_urls
  attr_accessor :theme_cache_key
  def initialize(namespace, script, script_sha)
    @policy = OwnedCachePolicy.new
    @host = ENV.fetch("FIDELITY_VALKEY_HOST")
    @port = ENV.fetch("FIDELITY_VALKEY_PORT").to_i
    @namespace, @script, @script_sha = namespace, script, script_sha
    @runtime_pid = Process.pid
    @events = []
    @lock = Mutex.new
    @closed = false
    @category_urls = {}
    @assignment_key = nil
    @assignment_updated = false
    @publication_count = 0
    @origins_seen = {}
    @closing = false
    @refusal = nil
  end
  def note_category_url(key, value)
    @lock.synchronize { @category_urls[key] = value }
  end
  def event(name)
    @lock.synchronize { @events << name }
    nil
  end
  def check!(host, port)
    raise ArgumentError, "category cache runtime ownership" unless Process.pid == @runtime_pid && !@closed
    @policy.check!(host, port)
  end
  def observe(command, response)
    CategoryCacheOutput.synchronize { @policy.observe(command, response) }
    if command[0] == "EVAL" || command[0] == "EVALSHA"
      raise "category cache publication reply" unless response.is_a?(Integer) && response > 0
      @lock.synchronize do
        @publication_count += 1 if command[12] == channel
        @events << "publish_reply"
      end
    end
  end
  def connect
    check!(@host, @port)
    connection = CategoryCacheConnection.new(@host, @port, self, self)
    begin
      info = connection.dispatch(["INFO", "server"])
      pid = info.to_s.split("\n").find { |line| line.start_with?("process_id:") }.to_s.split(":").last.to_i
      raise ArgumentError, "category cache socket owner" unless pid == ENV.fetch("FIDELITY_VALKEY_PID").to_i
      connection.dispatch(["CLIENT", "SETNAME", "category-cache:#{@runtime_pid}"])
      connection
    rescue Exception
      connection.close
      raise
    end
  end
  def assignment_begin(key)
    @lock.synchronize do
      @assignment_key = key
      @assignment_updated = false
      @events << "assignment_begin"
    end
  end
  def assignment_updated(key)
    @lock.synchronize do
      raise "category cache assignment ownership" unless @assignment_key == key
      @assignment_updated = true
      @events << "local_update"
    end
  end
  def refusal; @refusal; end
  def validate_incoming(row)
    raise ArgumentError, "category cache inbound transport namespace" unless row[0] == "message" && row[1] == "_message_bus_0" && row[2].is_a?(String)
    if row[2] == "$$UNSUBSCRIBE"
      raise ArgumentError, "category cache unsolicited shutdown" unless @closing
      return true
    end
    message = CategoryCacheMessageBus::Message.decode(row[2])
    raise ArgumentError, "category cache inbound namespace" unless message.channel == channel || message.channel == heartbeat_channel
    payload = JSON.parse(message.data)
    raise ArgumentError, "category cache inbound targets" unless payload["user_ids"] == [-1] && payload["group_ids"].nil? && payload["client_ids"].nil?
    data = payload["data"]
    if message.channel == heartbeat_channel
      raise ArgumentError, "category cache foreign heartbeat" unless data == Process.pid
    else
      raise ArgumentError, "category cache inbound payload" unless admitted_entry?(data) && data["op"] == "set" && data["marshalled"] == false && data["key"].is_a?(String) && data["value"].is_a?(String)
      raise ArgumentError, "category cache foreign origin/version" unless data["origin"] == @origins_seen[data["hash_key"]] && data["app_version"] == CategoryCacheDiscourseBinding.git_version
    end
    true
  rescue Exception => error
    @refusal = error.message
    raise
  end
  def admitted_entry?(data)
    key = data["key"]
    return false unless key.is_a?(String)
    if data["hash_key"] == "category_url"
      key.match?(/\A[0-9]+\z/)
    elsif data["hash_key"] == "icon_manager"
      ["opengraph_image_url", "favicon_url", "apple_touch_icon_url"].include?(key)
    elsif data["hash_key"] == "scheme_hex_for_name"
      key.match?(/\Aheader_background(?:_[0-9]+)?\z/)
    elsif !@theme_cache_key.nil? && data["hash_key"] == @theme_cache_key
      key == "compiler_version"
    else
      false
    end
  end
  def publication_count; @lock.synchronize { @publication_count }; end
  def finish!; @closed = true; end
  def heartbeat_channel; "/__mb_keepalive__/$|$#{@namespace}"; end
  def channel
    "/distributed_hash$|$#{@namespace}"
  end
  def authorize(command)
    check!(@host, @port)
    name = command[0].to_s.upcase
    case name
    when "INFO"
      raise ArgumentError, "category cache INFO scope" unless command == ["INFO", "server"]
    when "SUBSCRIBE", "UNSUBSCRIBE"
      raise ArgumentError, "category cache subscription namespace" unless command == [name, "_message_bus_0"]
    when "PUBLISH"
      raise ArgumentError, "category cache cleanup namespace" unless command == [name, "_message_bus_0", "$$UNSUBSCRIBE"]
      @closing = true
    when "CLIENT"
      raise ArgumentError, "category cache client ownership command" unless command == ["CLIENT", "LIST"] || command == ["CLIENT", "SETNAME", "category-cache:#{@runtime_pid}"]
    when "PUBSUB"
      raise ArgumentError, "category cache consumer namespace" unless command == ["PUBSUB", "NUMSUB", "_message_bus_0"]
    when "SET"
      raise ArgumentError, "category cache readonly probe scope" unless command == ["SET", "__mb_is_readonly", "1"]
    when "GET", "MGET", "ZRANGEBYSCORE"
      allowed = ["__mb_global_id_n", "__mb_global_backlog_n", "__mb_backlog_id_n_#{channel}", "__mb_backlog_n_#{channel}"]
      raise ArgumentError, "category cache read namespace" unless allowed.include?(command[1].to_s)
    when "EVAL", "EVALSHA"
      raise ArgumentError, "category cache script identity" unless command[1] == (name == "EVAL" ? @script : @script_sha)
      target = command[12]
      raise ArgumentError, "category cache publication channel" unless target == channel || target == heartbeat_channel
      expected = ["__mb_global_id_n", "__mb_backlog_id_n_#{target}", "__mb_backlog_n_#{target}", "__mb_global_backlog_n", "_message_bus_0"]
      raise ArgumentError, "category cache publication namespace" unless command[2].to_i == 5 && command[3, 5] == expected
      wire = command[8].to_s
      encoded_channel = target.gsub("|", "$$123$$")
      raise ArgumentError, "category cache wire channel" unless wire.start_with?(encoded_channel + "|")
      payload = JSON.parse(wire[(encoded_channel.length + 1)..-1])
      data = payload["data"]
      raise ArgumentError, "category cache publication target" unless payload["user_ids"] == [-1] && payload["group_ids"].nil? && payload["client_ids"].nil?
      if target == heartbeat_channel
        raise ArgumentError, "category heartbeat payload" unless data == Process.pid
        return true
      end
      raise ArgumentError, "category cache publication bypassed real defer" if Thread.current == Thread.main
      @lock.synchronize do
        raise ArgumentError, "category cache publication/update order" if @assignment_updated
      end
      raise ArgumentError, "category cache publication scope" unless admitted_entry?(data) && data["op"] == "set" && data["marshalled"] == false && data["key"].is_a?(String) && data["value"].is_a?(String)
      raise ArgumentError, "category cache outgoing origin/version" unless data["origin"].is_a?(String) && data["origin"].end_with?(Process.pid.to_s) && data["app_version"] == CategoryCacheDiscourseBinding.git_version
      @origins_seen[data["hash_key"]] = data["origin"]
      event("publish_dispatch")
    else
      raise ArgumentError, "unadmitted category cache command #{name}"
    end
    true
  end
end
class CategoryCacheConnection < PortableRedisConnection
  def dispatch(command)
    @endpoint_policy.authorize(command)
    @mutex.synchronize do
      raise IOError, "closed category cache socket" if @socket.nil?
      data = PortableRedisConnection.encode(command)
      offset = 0
      while offset < data.bytesize
        count = @socket.write(data.byteslice(offset, data.bytesize - offset))
        raise IOError, "category cache transport stalled" unless count > 0
        offset += count
      end
      begin
        response = read_reply
      rescue IOError => error
        raise CategoryCacheRedisClient::CommandError, error.message.delete_prefix("Redis error: ") if error.message.start_with?("Redis error: ")
        raise
      end
      @observer.observe(command, response)
      response
    end
  end
end
class CategoryCacheRedisClient
  class CommandError < StandardError; end
  class ReadOnlyError < CommandError; end
  class Events
    def subscribe(&block); @subscribe = block; end
    def unsubscribe(&block); @unsubscribe = block; end
    def message(&block); @message = block; end
    def receive(row)
      case row[0]
      when "subscribe" then @subscribe.call
      when "unsubscribe" then @unsubscribe.call
      when "message" then @message.call(row[1], row[2])
      else raise "unknown category cache subscription reply"
      end
    end
  end
  class << self
    attr_accessor :lease
  end
  def initialize(config)
    @lease = CategoryCacheRedisClient.lease
    raise ArgumentError, "unbound category cache lease" if @lease.nil?
    raise ArgumentError, "category cache Redis configuration" unless config == {host: @lease.host, port: @lease.port, db: 0}
    @connection = @lease.connect
    @unsubscribed = false
  end
  def set(key, value); @connection.dispatch(["SET", key, value]); end
  def get(key); @connection.dispatch(["GET", key]); end
  def mget(*keys); @connection.dispatch(["MGET", *keys]); end
  def zrangebyscore(key, low, high); @connection.dispatch(["ZRANGEBYSCORE", key, low, high]); end
  def evalsha(script, params); evaluate("EVALSHA", script, params); end
  def eval(script, params); evaluate("EVAL", script, params); end
  def verify_consumers!
    counts = @connection.dispatch(["PUBSUB", "NUMSUB", "_message_bus_0"])
    raise ArgumentError, "category cache external/missing consumer" unless counts == ["_message_bus_0", 1]
    clients = @connection.dispatch(["CLIENT", "LIST"]).to_s
    unnamed = 0
    clients.split("\n").each do |line|
      name = +""
      address = +""
      database = +""
      line.split(" ").each do |pair|
        name = pair.delete_prefix("name=") if pair.start_with?("name=")
        address = pair.delete_prefix("addr=") if pair.start_with?("addr=")
        database = pair.delete_prefix("db=") if pair.start_with?("db=")
      end
      if name == ""
        unnamed += 1
      else
        raise ArgumentError, "category cache foreign runtime consumer" unless name == "category-cache:#{Process.pid}"
      end
      raise ArgumentError, "category cache external client address" unless address.start_with?("127.0.0.1:") && database == "0"
    end
    raise ArgumentError, "category cache unknown unnamed consumers" unless unnamed == 1
    true
  end
  def evaluate(command, script, params)
    verify_consumers!
    keys = params.fetch(:keys)
    @connection.dispatch([command, script, keys.length, *keys, *params.fetch(:argv)])
  end
  def publish(channel, message); @connection.dispatch(["PUBLISH", channel, message]); end
  def disconnect!; @connection.close; end
  def subscribe(channel)
    events = Events.new
    yield events
    ack = @connection.dispatch(["SUBSCRIBE", channel])
    @lease.event("subscription_ack")
    events.receive(ack)
    until @unsubscribed
      row = @connection.read_reply
      @lease.check!(@lease.host, @lease.port)
      @lease.validate_incoming(row)
      events.receive(row)
    end
  end
  def unsubscribe
    @unsubscribed = true
    @connection.dispatch(["UNSUBSCRIBE", "_message_bus_0"])
  end
end
# Category's class-variable cache is never weakly collected during this scope.
class CategoryCacheRootRef
  class RefError < StandardError; end
  def initialize(cache)
    raise ArgumentError, "category cache registration scope" unless cache.key.is_a?(String) && (["category_url", "icon_manager", "scheme_hex_for_name"].include?(cache.key) || (!CategoryCacheBootstrap.lease.theme_cache_key.nil? && cache.key == CategoryCacheBootstrap.lease.theme_cache_key))
    @cache = cache
  end
  def identity; @cache.identity; end
  def key; @cache.key; end
  def hash(site); @cache.hash(site); end
end
class CategoryCacheStats
  def initialize(capacity)
    raise ArgumentError, "category defer statistics capacity" unless capacity == 100
    @values = {}
  end
  def [](key)
    raise ArgumentError, "category defer descriptor" unless ["category_url_set", "icon_manager_set", "scheme_hex_for_name_set"].include?(key) || (!CategoryCacheBootstrap.lease.theme_cache_key.nil? && key == CategoryCacheBootstrap.lease.theme_cache_key + "_set")
    @values[key]
  end
  def []=(key, value)
    raise ArgumentError, "category defer descriptor" unless ["category_url_set", "icon_manager_set", "scheme_hex_for_name_set"].include?(key) || (!CategoryCacheBootstrap.lease.theme_cache_key.nil? && key == CategoryCacheBootstrap.lease.theme_cache_key + "_set")
    @values[key] = value
  end
  def to_a; @values.to_a; end
end
