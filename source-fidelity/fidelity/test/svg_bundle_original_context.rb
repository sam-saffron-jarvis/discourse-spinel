# frozen_string_literal: true
require_relative 'original_svg_bundle_source'
class ObservedOriginalCategoryCache
  def defer_get_set_theme_sprites(keys, key_block)
    defer_get_set_bulk(keys, key_block) do |missing|
      values = yield missing
      missing.zip(values).each { |key, value| CategoryCacheBootstrap.lease.note_svg_sprite_value(key_block.call(key), value) }
      CategoryCacheBootstrap.lease.note_svg_bulk_enqueue(missing.size)
      values
    end
  end
end
module SvgBundleBootstrap
  def self.source_path(id); OriginalRequestSvgSource.path(id); end
  def self.source_bundle(id); OriginalRequestSvgSource.bundle(id); end
  def self.source_version(id); OriginalRequestSvgSource.version(id); end
  def self.source_icons(id); OriginalRequestSvgSource.all_icons(id); end
  def self.source_core; OriginalRequestSvgSource.core_svgs; end
  def self.source_custom(id); OriginalRequestSvgSource.custom_svgs(id); end
end
module RequestSvgBootstrap
  def self.path(id); SvgBundleBootstrap.acquire_path(id); end
end
class OriginalListBodyContext
  include SvgBundleViewProtocol
  def observation; svg_bundle_stage_observation; end
end
