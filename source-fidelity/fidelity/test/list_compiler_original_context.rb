# frozen_string_literal: true
require_relative "original_importmap_prefix"
require_relative "original_importmap_registry"
require_relative "original_compiler_helpers"
require_relative "original_theme_js_prefix"
module ListThemeCompilerSource
  def self.get_set_cache(key)
    if key != "compiler_version"
      raise HtmlRenderingBoundary, "actual source/V8 theme compiler version acquired; Theme extra_js array cache/bake capability pending, not a permission barrier"
    end
    CategoryCacheBootstrap.theme_compiler_cache.defer_get_set(key) { yield }
  end
end
module OriginalCompilerHelpers
  module Theme
    def self.js_asset_info(id, **options); ListThemeCompilerSource.js_asset_info(id, **options); end
  end
end
module ObservedOriginalCompilerHelpers
  include OriginalCompilerHelpers
  def theme_js_assets
    @events << "theme_compiler_version_acquisition"
    super
  end
end
class OriginalListBodyContext
  include OriginalImportMapPrefix
  include ListCompilerViewProtocol
  include ObservedOriginalCompilerHelpers
  def observation; compiler_stage_observation; end
end

module CategoryCacheBootstrap
  def self.theme_compiler_cache
    return acquired_theme_compiler_cache unless acquired_theme_compiler_cache.nil?
    lease.theme_cache_key = ListCompilerSource::THEME_CACHE_KEY
    self.acquired_theme_compiler_cache = ObservedOriginalCategoryCache.new(ListCompilerSource::THEME_CACHE_KEY, manager: manager)
    raise "compiler cache subscription registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 4
    acquired_theme_compiler_cache
  end
end
