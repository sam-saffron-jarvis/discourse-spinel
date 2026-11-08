# frozen_string_literal: true
require_relative 'head_yield_source'
module HeadYieldViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition', 'view_flow_receiver', 'layout_head_yield_returned', 'markdown_alternate_acquisition']
  end
  def head_yield_capability(slot)
    raise ArgumentError, 'unsupported layout yield slot' unless slot == :head
    @events << 'layout_head_yield_acquisition'
    value = source_head_layout_for(slot)
    value = ActionView::HtmlFragment.new('') if ENV.fetch('FIDELITY_HEAD_YIELD_FAULT', '') == 'wrong-result'
    first = get(:head)
    value = first if ENV.fetch('FIDELITY_HEAD_YIELD_FAULT', '') == 'alias-return'
    raise 'head view-flow warm identity changed' unless first.equal?(get(:head))
    raise 'head view-flow fresh return identity changed' if value.equal?(first)
    raise 'head view-flow return bytes changed' unless value.to_s == first.to_s
    raise 'head view-flow trust changed' unless value.html_safe?
    @actual_head_yield = value.to_s
    @events << 'layout_head_yield_returned'
    value
  end
  def markdown_alternate_link_tag
    @events << 'markdown_alternate_acquisition'
    raise HtmlRenderingBoundary, 'actual source layout_for head yielded captured bytes; markdown alternate helper acquisition pending'
  end
  def head_yield_stage_observation
    record = head_configuration_stage_observation
    value = @actual_head_yield
    raise 'captured head yield bytes changed' unless value.is_a?(String) && value == @head_output && record[:layout_prefix].include?(value)
    record[:head_yield] = {value: value, bytes: value.bytesize, sha256: Digest::SHA256.hexdigest(value), warm_read_identity: true, fresh_safe_copy: true}
    record
  end
end
class ListBodyContext
  include SourceHeadLayoutFor
  include HeadYieldViewProtocol
  def get(slot)
    raise ArgumentError, 'unsupported head flow read profile' unless slot == :head && @body_returned
    source = @head_output
    raise TypeError, 'captured head slot is not String' unless source.is_a?(String)
    if @head_flow_fragment.nil?
      @head_flow_source = source.dup.freeze
      data = ENV.fetch('FIDELITY_HEAD_YIELD_FAULT', '') == 'escaped-head' ? ERB::Util.html_escape(source) : source
      @head_flow_fragment = ActionView::HtmlFragment.new(data)
    end
    raise ArgumentError, 'unsupported late/interleaved head capture' unless source == @head_flow_source
    @head_flow_fragment
  end
  def observation; head_yield_stage_observation; end
end
