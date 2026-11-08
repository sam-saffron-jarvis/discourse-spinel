# frozen_string_literal: true
# Single-site dependency binding to actual readonly emitted AR/PG, not a DB fake.
module CategoryCacheDbBindings
  class Connection
    def verify!
      Db.with_connection do
        connection = ::ActiveRecord::Base.connection
        raise "category deferred worker PG is writable" unless connection.select_value("SHOW default_transaction_read_only") == "on"
      end
      true
    end
  end
  class Pool
    def connected?
      Db.with_connection { ::ActiveRecord::Base.connection.select_value("SELECT 1") == 1 }
    end
  end
  class Handler
    def clear_active_connections!
      ::ActiveRecord::Base.connection_pool.release_connection
    end
  end
  class Base
    def self.connection; Connection.new; end
    def self.connection_pool; Pool.new; end
    def self.connection_handler; Handler.new; end
  end
end
module CategoryCacheDiscourseBinding
  def self.git_version; PortableGitVersion.read(PortableGitVersion.application_root); end
  def self.handle_job_exception(error, context = {})
    raise HtmlRenderingBoundary, "category deferred error reporter requires guarded Logster capability: #{error.class}: #{error.message}"
  end
end
module CategoryCacheApplication
  ActiveRecord = CategoryCacheDbBindings
  Discourse = CategoryCacheDiscourseBinding
end
module OriginalCategoryCacheApplication
  ActiveRecord = CategoryCacheDbBindings
  Discourse = CategoryCacheDiscourseBinding
end
module CategoryCacheBootstrap
  @initial_threads = Thread.list.size
  class << self
    attr_accessor :cache, :bus, :manager, :lease, :scheduler, :ready, :initial_threads, :acquired_icon_cache, :acquired_color_cache, :acquired_theme_compiler_cache
  end
  def self.configure(configuration, namespace)
    self.ready = false
    self.initial_threads = Thread.list.size
    fault = ENV.fetch("FIDELITY_CACHE_FAULT", "")
    namespace = "negative-other-site" if fault == "wrong-namespace"
    raise ArgumentError, "category cache requires real async development profile" unless Rails.env.development? && !Rails.env.test?
    configuration.database_hostname
    raise ArgumentError, "unsupported category cache Redis database" unless configuration.value("redis_db") == 0 && !configuration.value("message_bus_redis_enabled")
    %w[redis_username redis_password redis_replica_host].each do |key|
      raise ArgumentError, "unsupported category cache backend configuration #{key}" if configuration.value(key)
    end
    raise ArgumentError, "unsupported category cache SSL" if configuration.value("redis_use_ssl")
    raise ArgumentError, "category cache site namespace" unless namespace == CategoryCacheApplication::RailsMultisite::ConnectionManagement::DEFAULT
    raise ArgumentError, "unsupported skip Redis category cache" if configuration.value("skip_redis")
    self.lease = CategoryCacheLease.new(namespace, CategoryCacheMessageBus::Backends::Redis::LUA_PUBLISH, CategoryCacheMessageBus::Backends::Redis::LUA_PUBLISH_SHA1)
    lease.instance_variable_set(:@runtime_pid, Process.pid + 1) if fault == "wrong-runtime"
    lease.check!(lease.host, 6399) if fault == "shared-endpoint"
    lease.check!(lease.host, 1) if fault == "unknown-endpoint"
    lease.check!(lease.host, lease.port)
    CategoryCacheRedisClient.lease = lease
    CategoryCacheMessageBus.site_id_lookup { namespace }
    self.bus = CategoryCacheMessageBus::Instance.new
    bus.redis_config = {host: lease.host, port: lease.port, db: 0}
    bus.site_id_lookup { namespace }
    bus.backend_instance.max_backlog_size = configuration.value("message_bus_max_backlog_size")
    bus.backend_instance.clear_every = configuration.value("message_bus_clear_every")
    acquire_cache
    raise "category cache subscription missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 1
    bus.backend_instance.owned_fixture_client.verify_consumers!
    lease.event("cache_registered")
    self.ready = true
    if fault == "wrong-message-namespace"
      lease.validate_incoming(["message", "_message_bus_0", "1|1|foreign|{}"])
    end
    nil
  end
  def self.acquire_cache
    self.manager = CategoryCacheMessageBus::DistributedCache::Manager.new(bus)
    self.scheduler = CategoryCacheApplication::Scheduler::Defer
    self.cache = CategoryCacheApplication::DistributedCache.new("category_url", manager: manager)
  end
  def self.body_icon_cache
    return acquired_icon_cache unless acquired_icon_cache.nil?
    self.acquired_icon_cache = CategoryCacheApplication::DistributedCache.new("icon_manager", manager: manager)
    raise "icon cache subscription/registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 2
    lease.event("icon_cache_registered")
    acquired_icon_cache
  end
  def self.layout_color_cache
    return acquired_color_cache unless acquired_color_cache.nil?
    self.acquired_color_cache = CategoryCacheApplication::DistributedCache.new("scheme_hex_for_name", manager: manager)
    raise "layout color cache registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 3
    lease.event("layout_color_cache_registered")
    acquired_color_cache
  end
  def self.close!
    error = nil
    rows = []
    worker_before_stop = scheduler.nil? ? nil : scheduler.instance_variable_get(:@thread)
    begin
      scheduler.stop!(finish_work: true) unless scheduler.nil?
    rescue Exception => caught
      error = caught
    ensure
      begin
        reactor = scheduler.instance_variable_get(:@reactor) unless scheduler.nil?
        reactor.stop unless reactor.nil?
        if ready
          rows = bus.backend_instance.owned_fixture_client.zrangebyscore("__mb_backlog_n_#{lease.channel}", "-inf", "+inf")
        end
      rescue Exception => caught
        error ||= caught
      ensure
        begin
          bus.destroy unless bus.nil?
        rescue Exception => caught
          error ||= caught
        end
      end
    end
    record = {ready: ready == true, threads_before: initial_threads, threads_after: Thread.list.size,
      namespace: lease.nil? ? nil : lease.namespace, cache: {}, publications: 0, received_callbacks: 0,
      queued: 0, finished: 0, errors: 0, server_values: {}, icon_cache: {}, server_icon_values: {}, color_cache: {}, server_color_values: {}, theme_compiler_cache: {}, server_theme_compiler_values: {}, pending: 0, pending_stop_sentinels: 0}
    begin
      raise "category cache thread cleanup leaked" unless Thread.list.size == initial_threads
      if ready
        raise "category defer forced synchronous/test mode" unless scheduler.async == true
        scheduler.stats.each do |entry|
          data = entry[1]
          record[:queued] += data[:queued]
          record[:finished] += data[:finished]
          record[:errors] += data[:errors]
        end
        record[:pending] = scheduler.length
        # Original stop!(finish_work:true) enqueues its finish sentinel even
        # when no worker was ever started. This is not an unexecuted cache job.
        if worker_before_stop.nil? && record[:queued] == 0 && record[:pending] == 1
          record[:pending_stop_sentinels] = 1
        end
        record[:cache] = cache.category_values
        record[:icon_cache] = acquired_icon_cache.category_values unless acquired_icon_cache.nil?
        record[:color_cache] = acquired_color_cache.category_values unless acquired_color_cache.nil?
        record[:theme_compiler_cache] = acquired_theme_compiler_cache.category_values unless acquired_theme_compiler_cache.nil?
        record[:publications] = lease.publication_count
        record[:received_callbacks] = lease.events.count { |event| event == "manager_process_message" }
        server_values = {}
        server_icon_values = {}
        server_color_values = {}
        server_theme_compiler_values = {}
        rows.each do |row|
          message = CategoryCacheMessageBus::Message.decode(row)
          raise "category cache server namespace" unless message.channel == lease.channel
          payload = JSON.parse(message.data)
          data = payload["data"]
          raise "category cache server target" unless payload["user_ids"] == [-1] && ["category_url", "icon_manager", "scheme_hex_for_name", lease.theme_cache_key].include?(data["hash_key"]) && data["op"] == "set" && data["marshalled"] == false
          raise "category cache server origin/version" unless data["origin"].end_with?(Process.pid.to_s) && data["app_version"] == CategoryCacheDiscourseBinding.git_version
          if data["hash_key"] == "category_url"
            server_values[data["key"]] = data["value"]
          elsif data["hash_key"] == "icon_manager"
            server_icon_values[data["key"]] = data["value"]
          elsif data["hash_key"] == "scheme_hex_for_name"
            server_color_values[data["key"]] = data["value"]
          else
            server_theme_compiler_values[data["key"]] = data["value"]
          end
        end
        record[:server_values] = server_values
        record[:server_icon_values] = server_icon_values
        record[:server_color_values] = server_color_values
        record[:server_theme_compiler_values] = server_theme_compiler_values
        if error.nil?
          raise "category cache refused inbound message: #{lease.refusal}" unless lease.refusal.nil?
          record[:cache].each do |key, value|
            hit = cache.defer_get_set(key) { raise "genuine category cache hit recomputed" }
            raise "genuine category cache hit changed URL" unless hit == value
          end
          unless acquired_icon_cache.nil?
            record[:icon_cache].each do |key, value|
              hit = acquired_icon_cache.defer_get_set(key) { raise "genuine icon cache hit recomputed" }
              raise "genuine icon cache hit changed URL" unless hit == value
            end
          end
          unless acquired_color_cache.nil?
            record[:color_cache].each do |key, value|
              hit = acquired_color_cache.defer_get_set(key) { raise "genuine layout color hit recomputed" }
              raise "genuine layout color hit changed" unless hit == value
            end
          end
          unless acquired_theme_compiler_cache.nil?
            record[:theme_compiler_cache].each do |key, value|
              hit = acquired_theme_compiler_cache.defer_get_set(key) { raise "genuine compiler version hit recomputed" }
              raise "genuine compiler version hit changed" unless hit == value
            end
          end
          raise "category cache deferred completion missing" unless record[:queued] == record[:finished] && record[:errors] == 0 && record[:pending] == record[:pending_stop_sentinels]
          raise "missing category cache publication" unless record[:queued] == record[:publications] && rows.size == record[:publications]
          raise "category cache subscription callback missing" unless record[:received_callbacks] >= record[:publications]
          raise "category cache real server/local values differ" unless record[:cache] == server_values
          raise "icon cache real server/local values differ" unless record[:icon_cache] == server_icon_values
          raise "color cache real server/local values differ" unless record[:color_cache] == server_color_values
          raise "compiler cache real server/local values differ" unless record[:theme_compiler_cache] == server_theme_compiler_values
        end
      end
    rescue Exception => caught
      error ||= caught
    ensure
      puts "FIDELITY_CATEGORY_CACHE_LIFECYCLE " + JSON.generate(record)
      lease.finish! unless lease.nil?
    end
    raise error unless error.nil?
    nil
  end
end

class ListTemplatePrefixContext
  def observation
    record = prefix_observation
    raise "missing genuine acquired category URL" unless @acquired_category_url.is_a?(String) && !@acquired_category_url.empty?
    record[:category_url] = @acquired_category_url
    record[:capability_dispatched] = true
    record
  end
  def category_url_capability(category)
    @category_attempt = category.id
    value = category.url
    category_url_acquired(value)
  end
  def category_url_acquired(value)
    @acquired_category_url = value
    @events << "category_url_capability_refusal"
    raise HtmlRenderingBoundary, "category URL/cache acquired; further template continuation not yet installed"
  end
end
