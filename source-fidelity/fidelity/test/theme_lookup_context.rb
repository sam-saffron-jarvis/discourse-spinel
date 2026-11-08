# frozen_string_literal: true
require_relative 'theme_lookup_source'
require_relative 'theme_lookup_helpers'
module ThemeFieldReadBootstrap
  def self.callback_count; @callback_count ||= 0; end
  def self.note_callback; @callback_count = callback_count + 1; nil; end
  def self.row_count; @row_count ||= 0; end
  def self.note_read_row; @row_count = row_count + 1; nil; end
  def self.computations; @computations ||= 0; end
  def self.note_keys(keys)
    @computations = computations + 1
    @last_keys ||= keys
    @all_keys ||= []
    @all_keys << keys
    nil
  end
  def self.last_keys; @last_keys; end
  def self.all_keys; @all_keys ||= []; end
end
module ThemeFieldViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition']
  end
  def preload_script(path, **options)
    @events << 'core_browser_detect_acquisition'
    raise HtmlRenderingBoundary, 'actual Theme translation lookup returned; core browser-detect preload acquisition pending'
  end
  def theme_field_stage_observation
    record = client_override_stage_observation
    value = @actual_theme_translations
    raise 'actual Theme translation result not acquired' unless value.is_a?(String)
    keys = ThemeFieldReadBootstrap.last_keys
    raise 'actual Theme field query not entered' unless keys.is_a?(Array) && !keys.empty? && ThemeFieldReadBootstrap.computations > 0
    raise 'applicable Theme field callback omitted' unless ThemeFieldReadBootstrap.row_count == ThemeFieldReadBootstrap.callback_count
    record[:theme_translations] = {value: value, query_keys: keys, computations: ThemeFieldReadBootstrap.computations, callbacks: ThemeFieldReadBootstrap.callback_count, rows: ThemeFieldReadBootstrap.row_count}
    record
  end
end
class ListBodyContext
  include ThemeLookupHelpers
  include ThemeFieldViewProtocol
  def theme_translations_lookup
    @events << 'theme_translations_acquisition'
    value = source_theme_translations_lookup
    @actual_theme_translations = value.to_s
    @events << 'theme_translations_returned'
    value
  end
  def observation; theme_field_stage_observation; end
end
