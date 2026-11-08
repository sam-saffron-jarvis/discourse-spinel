# frozen_string_literal: true
require_relative 'head_tag_helpers'
module HeadTagViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition']
  end
  def theme_lookup(name)
    @events << 'theme_head_tag_acquisition'
    value = source_head_tag_lookup(name)
    @actual_head_tag = value.to_s
    @events << 'theme_head_tag_returned'
    value
  end
  def render_google_tag_manager_head_code
    @events << 'analytics_head_acquisition'
    raise HtmlRenderingBoundary, 'actual Theme head_tag two-key lookup returned; analytics helper acquisition pending'
  end
  def head_tag_stage_observation
    record = core_preload_stage_observation
    value = @actual_head_tag
    raise 'actual head_tag field lookup not acquired' unless value.is_a?(String)
    keys = ThemeFieldReadBootstrap.all_keys
    raise 'actual common/desktop head_tag query missing' unless keys.any? { |group| group.any? { |tuple| tuple[1] == :common && tuple[2] == :head_tag } }
    record[:head_tag] = {value: value, all_query_keys: keys, computations: ThemeFieldReadBootstrap.computations, rows: ThemeFieldReadBootstrap.row_count, callbacks: ThemeFieldReadBootstrap.callback_count}
    record
  end
end
class ListBodyContext
  include HeadTagHelpers
  include HeadTagViewProtocol
  def observation; head_tag_stage_observation; end
end
