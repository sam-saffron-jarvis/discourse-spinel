# frozen_string_literal: true
require_relative 'core_preload_helpers'
module CorePreloadViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition']
  end
  def preload_script(script, type_module: false, attrs: {})
    @events << 'core_browser_detect_acquisition'
    value = source_preload_script(script, type_module: type_module, attrs: attrs)
    @core_browser_markup = value.to_s
    @events << 'core_browser_detect_returned'
    value
  end
  def module_preloads_for(*scripts)
    @events << 'core_module_preloads_acquisition'
    @core_expected_chunks = scripts.compact.flat_map { |script| request_assets.script_chunks[script] }.compact.uniq
    value = source_module_preloads_for(*scripts)
    value = ActionView::HtmlFragment.new('') if ENV.fetch('FIDELITY_CORE_PRELOAD_FAULT', '') == 'omit-modules'
    @core_module_markup = value.to_s
    @events << 'core_module_preloads_returned'
    value
  end
  def theme_lookup(name)
    @events << 'theme_head_tag_acquisition'
    raise HtmlRenderingBoundary, 'actual core script/module preloads returned; Theme head_tag bulk acquisition pending'
  end
  def core_preload_stage_observation
    record = theme_field_stage_observation
    script = @core_browser_markup
    modules = @core_module_markup
    chunks = @core_expected_chunks
    raise 'actual core browser-detect preload missing' unless script.is_a?(String) && script.include?('data-discourse-entrypoint="js/browser-detect"') && script.include?('defer')
    raise 'actual core module preload missing' unless modules.is_a?(String) && chunks.is_a?(Array) && !chunks.empty? && modules.scan('rel="modulepreload"').size == chunks.size
    urls = []
    chunks.each do |chunk|
      url = @asset_urls[chunk]
      raise 'core module preload URL mismatch' unless url.is_a?(String) && modules.include?('href="' + url + '"')
      urls << url
    end
    raise 'core browser preload storage missing' unless controller.asset_preload_links.is_a?(Array) && controller.asset_preload_links.size == 3
    record[:core_preloads] = {browser_markup: script, module_markup: modules, chunks: chunks, urls: urls}
    record
  end
end
class ListBodyContext
  include CorePreloadHelpers
  include CorePreloadViewProtocol
  def observation; core_preload_stage_observation; end
end
