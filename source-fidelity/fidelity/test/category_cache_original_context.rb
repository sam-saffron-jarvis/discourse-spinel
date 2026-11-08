# frozen_string_literal: true
# Isolated original methods, not Rails HTML. Keep the same guarded bus transport;
# compare raw original cache/WeakRef and Scheduler/WorkQueue/LRU/Timer bodies.
require "message_bus/distributed_cache"
require "message_bus/timer_thread"
require "lru_redux"
require_relative "original_category_cache_subscription"
require_relative "original_category_cache_application_source"
module MessageBus
  def self.site_id_lookup; CategoryCacheMessageBus.site_id_lookup; end
end
class ObservedOriginalCategoryManager < MessageBus::DistributedCache::Manager
  def process_message(message)
    CategoryCacheBootstrap.lease.event("manager_process_message")
    super
  end
end
class ObservedOriginalCategoryCache < OriginalCategoryCacheApplication::DistributedCache
  def category_values; hash; end
end
module CategoryCacheBootstrap
  def self.body_icon_cache
    return acquired_icon_cache unless acquired_icon_cache.nil?
    self.acquired_icon_cache = ObservedOriginalCategoryCache.new("icon_manager", manager: manager)
    raise "icon cache subscription/registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 2
    lease.event("icon_cache_registered")
    acquired_icon_cache
  end
  def self.layout_color_cache
    return acquired_color_cache unless acquired_color_cache.nil?
    self.acquired_color_cache = ObservedOriginalCategoryCache.new("scheme_hex_for_name", manager: manager)
    raise "layout color cache registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 3
    lease.event("layout_color_cache_registered")
    acquired_color_cache
  end
  def self.acquire_cache
    self.manager = ObservedOriginalCategoryManager.new(bus)
    self.scheduler = OriginalCategoryCacheApplication::Scheduler::Defer
    self.cache = ObservedOriginalCategoryCache.new("category_url", manager: manager)
  end
end
require_relative "category_cache_category_methods"
class OriginalTemplateCategory
  include CategoryCacheCategoryMethods
  def initialize(category, view)
    super(category)
    @view = view
    CategoryCacheCategoryMethods.class_variable_set(:@@url_cache, CategoryCacheBootstrap.cache)
  end
  def url
    value = super
    @view.instance_variable_set(:@category_attempt, __getobj__.id)
    @view.category_url_acquired(value)
  end
end
