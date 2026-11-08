# frozen_string_literal: true
require_relative 'original_svg_theme_icons_source'
class ObservedOriginalCategoryCache
  def defer_get_set_svg_theme_settings(key)
    defer_get_set(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_svg_theme_value(key, value)
      value
    end
  end
  def defer_get_set_svg_theme_modifier(key)
    defer_get_set(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_svg_theme_value(key, value)
      value
    end
  end
  def svg_theme_settings_hit(key)
    raise ArgumentError, 'unadmitted SVG Theme settings hit' unless CategoryCacheBootstrap.lease.svg_theme_settings_key?(key)
    value = self[key]
    raise TypeError, 'nonempty Theme settings Hash profile unacquired' unless value.is_a?(Hash) && value.empty?
    value
  end
end
module SvgThemeIcons
  def self.source_theme_icons(id); OriginalRequestSvgSource.theme_icons(id); end
end
class OriginalListBodyContext
  include SvgThemeIconsViewProtocol
  def observation; svg_theme_icons_stage_observation; end
end
