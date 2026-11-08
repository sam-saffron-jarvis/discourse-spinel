# frozen_string_literal: true
require_relative 'original_svg_cache_source'
class ObservedOriginalCategoryCache
  def defer_get_set_svg_reference(key)
    defer_get_set(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_svg_icons(key, value)
      value
    end
  end
  def defer_get_set_svg_icons(key); defer_get_set_svg_reference(key) { yield }; end
  def svg_values; hash.dup; end
end
module CategoryCacheBootstrap
  def self.svg_cache
    @acquired_svg_cache ||= ObservedOriginalCategoryCache.new('svg_sprite', manager: manager)
  end
end
module RequestSvgBootstrap
  def self.path(id); OriginalRequestSvgSource.path(id); end
  def self.badge_icons; OriginalRequestSvgSource.badge_icons; end
  def self.group_icons; OriginalRequestSvgSource.group_icons; end
end
module OriginalClientSetupHelpers::SvgSprite
  def self.path(id)
    RequestSvgBootstrap.bind(ClientHighlightBootstrap.events)
    ClientHighlightBootstrap.events << 'svg_sprite_acquisition'
    RequestSvgBootstrap.path(id)
  end
end
class OriginalListBodyContext
  include SvgCacheViewProtocol
  def observation; svg_cache_stage_observation; end
end
