# frozen_string_literal: true
require_relative 'svg_theme_icons_transport'
class SvgThemeSettingsParserRead
  def initialize(field); raise ArgumentError, 'nonempty SVG Theme settings parser profile unacquired'; end
  def load; raise ArgumentError, 'nonempty SVG Theme settings parser profile unacquired'; end
end
class SvgThemeSettingsManagerRead
  def self.create(*args); raise ArgumentError, 'nonempty SVG Theme settings manager profile unacquired'; end
end
require_relative 'svg_theme_icons_source'
module RequestSvgSource::Theme
  def self.where(**options); ::Theme.where(**options); end
end
class SvgThemeSettingsRead
  include SvgThemeSettingsMethods
  def initialize(theme)
    @theme_id = theme.id
    @settings_field_loaded = false
  end
  def id; @theme_id; end
  def settings_field
    unless @settings_field_loaded
      @settings_field = ThemeField.where(theme_id: id, target_id: ListThemeArraySource::TARGETS[:settings], name: 'yaml').first
      @settings_field_loaded = true
      SvgThemeIcons.note_settings_field(@settings_field)
    end
    @settings_field
  end
  def upload_fields
    ThemeField.where(theme_id: id, type_id: 2).preload(:upload)
  end
end
class SvgThemeModifierRead
  def initialize(theme_ids:); @theme_ids = theme_ids; end
  def svg_icons; SvgThemeIcons.lookup_modifier(@theme_ids, :svg_icons); end
end
module SvgThemeIcons
  def self.cache; CategoryCacheBootstrap.theme_compiler_cache; end
  def self.cache_settings(key)
    cache.defer_get_set_svg_theme_settings(key) do
      value = yield
      value = 'wrong-type' if ENV.fetch('FIDELITY_SVG_THEME_FAULT', '') == 'settings-type'
      value = {'unsupported' => 'value'} if ENV.fetch('FIDELITY_SVG_THEME_FAULT', '') == 'nonempty-settings'
      value
    end
  end
  def self.cache_modifier(key)
    cache.defer_get_set_svg_theme_modifier(key) do
      value = yield
      value = [12] if ENV.fetch('FIDELITY_SVG_THEME_FAULT', '') == 'modifier-type'
      value
    end
  end
  def self.note_settings_field(field)
    @settings_field_reads = (@settings_field_reads || 0) + 1
    @settings_field_present = !field.nil?
    nil
  end
  def self.settings_field_reads; @settings_field_reads || 0; end
  def self.settings_field_present; @settings_field_present; end
  def self.source_theme_icons(id); RequestSvgSource.theme_icons(id); end
  def self.settings_key(id)
    "settings_for_theme_#{id}_#{SvgExperimentalRead.enabled('granular_anonymous_and_logged_in_groups_permissions')}"
  end
  def self.modifier_key(ids)
    "#{ids.join(',')}:modifier:svg_icons:#{ListThemeCompilerSource.compiler_version}"
  end
end
module SvgThemeIconsViewProtocol
  def svg_theme_icons_stage_observation
    record = svg_icon_producers_stage_observation
    ids = ListThemeCompilerSource.transform_ids(theme_id)
    keys = ids.map { |id| SvgThemeIcons.settings_key(id) } + [SvgThemeIcons.modifier_key(ids)]
    cache = SvgThemeIcons.cache
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until keys.all? { |key| cache.category_values.key?(key) }
      raise 'SVG Theme settings/modifier publications missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    values = cache.category_values
    before = CategoryCacheBootstrap.lease.publication_count
    warm = SvgThemeIcons.source_theme_icons(theme_id)
    raise 'SVG Theme warm producer republished' unless before == CategoryCacheBootstrap.lease.publication_count
    expected = ThemeModifierSet.resolve_modifier_for_themes(ids, :svg_icons)
    raise 'SVG Theme icons differ from actual modifier rows' unless warm == expected
    raise 'SVG Theme settings read not entered' unless SvgThemeIcons.settings_field_reads > 0
    record[:svg_icon_producers][:remaining_theme_icons_acquired] = true
    record[:svg_theme_icons] = {theme_ids: ids, value: warm, keys: keys, settings_field_reads: SvgThemeIcons.settings_field_reads, settings_field_present: SvgThemeIcons.settings_field_present, values: keys.to_h { |key| [key, values[key]] }, warm_republished: false, nonempty_settings_or_uploads_supported: false}
    record
  end
end
class ListBodyContext
  include SvgThemeIconsViewProtocol
  def observation; svg_theme_icons_stage_observation; end
end
