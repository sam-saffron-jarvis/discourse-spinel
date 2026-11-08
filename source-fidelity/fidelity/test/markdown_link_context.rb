# frozen_string_literal: true
require_relative 'markdown_link_helpers'
module MarkdownLinkViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition', 'view_flow_receiver', 'layout_head_yield_returned', 'markdown_alternate_acquisition', 'markdown_alternate_returned', 'client_setup_tag_acquisition']
  end
  def markdown_alternate_link_tag
    @events << 'markdown_alternate_acquisition'
    @actual_markdown_feature = SiteSetting.enable_markdown_endpoints
    value = source_markdown_alternate_link_tag
    raise 'markdown link safety changed' unless value.nil? || value.html_safe?
    @actual_markdown_markup = value.nil? ? nil : value.to_s
    @events << 'markdown_alternate_returned'
    value
  end
  def markdown_alternate_url
    value = source_markdown_alternate_url
    @actual_markdown_url = value
    value
  end
  def metadata_tag_or_builder(name = nil, options = nil, open = false, escape = true)
    unless name.nil?
      raise ArgumentError, 'missing legacy metadata tag attributes' unless options.is_a?(Hash)
      return source_metadata_tag(name, options, open, escape)
    end
    @events << 'client_setup_tag_acquisition'
    raise HtmlRenderingBoundary, 'actual markdown/plugin head helpers returned; client setup tag builder acquisition pending'
  end
  def markdown_link_stage_observation
    record = head_yield_stage_observation
    raise 'markdown feature result is not Boolean' unless @actual_markdown_feature == true || @actual_markdown_feature == false
    if @actual_markdown_feature
      url = @actual_markdown_url
      markup = @actual_markdown_markup
      raise 'actual markdown link/href mismatch' unless url.is_a?(String) && markup.is_a?(String) && markup.include?('href="' + ERB::Util.html_escape(url) + '"')
    else
      raise 'disabled markdown link must be nil' unless @actual_markdown_markup.nil?
    end
    record[:markdown_link] = {enabled: @actual_markdown_feature, markup: @actual_markdown_markup, url: @actual_markdown_url}
    record
  end
end
class ListBodyContext
  include MarkdownLinkHelpers
  include MarkdownLinkViewProtocol
  def source_owned_title
    value = @title
    raise TypeError, 'captured title is not String' unless value.is_a?(String)
    value.dup
  end
  def tag(name = nil, options = nil, open = false, escape = true)
    metadata_tag_or_builder(name, options, open, escape)
  end
  def observation; markdown_link_stage_observation; end
end
