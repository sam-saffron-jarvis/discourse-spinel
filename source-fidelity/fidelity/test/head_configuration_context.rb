# frozen_string_literal: true
require_relative 'head_configuration_helpers'
module HeadConfigurationViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition']
  end
  def render_google_tag_manager_head_code
    @events << 'analytics_head_acquisition'
    @actual_gtm_output = source_render_google_tag_manager_head_code
  end
  def render_google_universal_analytics_code
    @events << 'analytics_google_universal_acquisition'
    @actual_ga_output = source_render_google_universal_analytics_code
  end
  def render_adobe_analytics_tags_code
    @events << 'analytics_adobe_acquisition'
    @actual_adobe_output = source_render_adobe_analytics_tags_code
  end
  def suppress_analytics_in_embed?; source_suppress_analytics_in_embed?; end
  def manifest_url
    @events << 'manifest_url_acquisition'
    value = source_manifest_url
    value += '#wrong' if ENV.fetch('FIDELITY_HEAD_CONFIG_FAULT', '') == 'wrong-manifest'
    @actual_manifest_url = value
    value
  end
  def include_ios_native_app_banner?
    @events << 'ios_banner_acquisition'
    @actual_ios_decision = source_include_ios_native_app_banner?
  end
  def ios_app_argument; source_ios_app_argument; end
  def head_yield_capability(slot)
    raise ArgumentError, 'unsupported layout yield slot' unless slot == :head
    @events << 'layout_head_yield_acquisition'
    raise HtmlRenderingBoundary, 'actual analytics/manifest/iOS head returned; original layout_for head view-flow acquisition pending'
  end
  def head_configuration_stage_observation
    record = head_tag_stage_observation
    raise 'actual manifest URL mismatch' unless @actual_manifest_url == Discourse.base_path + '/manifest.webmanifest'
    raise ArgumentError, 'unsupported active analytics/iOS acceptance profile' unless @actual_gtm_output.nil? && @actual_ga_output.nil? && @actual_adobe_output.nil? && !@actual_ios_decision
    record[:head_configuration] = {gtm_output: @actual_gtm_output, universal_analytics_output: @actual_ga_output, adobe_output: @actual_adobe_output, manifest_url: @actual_manifest_url, ios_banner_decision: @actual_ios_decision}
    record
  end
end
class ListBodyContext
  include HeadConfigurationHelpers
  include HeadConfigurationViewProtocol
  def layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @body_output = +''
    @output_buffer = self
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      raise 'head configuration layout prefix unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def observation; head_configuration_stage_observation; end
end
