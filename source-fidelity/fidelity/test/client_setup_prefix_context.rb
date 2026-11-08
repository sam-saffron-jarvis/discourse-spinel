# frozen_string_literal: true
require_relative 'client_setup_builder_source'
require_relative 'client_setup_prefix_source'
module ClientSetupReadBootstrap
  def self.begin_request(events)
    @inputs = {}
    @events = events
    nil
  end
  def self.inputs; @inputs ||= {}; end
  def self.record_input(name, value)
    raise TypeError, 'client setup prefix input is not nullable String' unless value.nil? || value.is_a?(String)
    inputs[name] = value.nil? ? nil : value.to_s
    value
  end
  def self.action_controller; self; end
  def self.asset_host; ListHeadImages.configuration.value('cdn_url'); end
  def self.asset_version
    events = @events
    raise 'client setup events not bound' unless events.is_a?(Array)
    events << 'asset_version_acquisition'
    raise HtmlRenderingBoundary, 'actual tag builder and client setup prefix acquired; asset-version graph/MessageBus lifecycle acquisition pending'
  end
end
module ClientSetupPrefixViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition', 'view_flow_receiver', 'layout_head_yield_returned', 'markdown_alternate_acquisition', 'markdown_alternate_returned', 'client_setup_tag_acquisition', 'client_setup_tag_returned', 'client_setup_data_acquisition', 'asset_version_acquisition']
  end
  def metadata_tag_or_builder(name = nil, options = nil, open = false, escape = true)
    unless name.nil?
      raise ArgumentError, 'missing legacy metadata tag attributes' unless options.is_a?(Hash)
      return source_metadata_tag(name, options, open, escape)
    end
    @events << 'client_setup_tag_acquisition'
    value = source_setup_tag_builder
    raise 'client setup tag builder warm identity changed' unless value.equal?(source_setup_tag_builder)
    raise 'client setup tag builder owner changed' unless setup_builder_owned?(value)
    @setup_builder_acquired = true
    @events << 'client_setup_tag_returned'
    value
  end
  def client_side_setup_data
    @events << 'client_setup_data_acquisition'
    raise 'client setup evaluated before actual tag receiver' unless @setup_builder_acquired
    ClientSetupReadBootstrap.begin_request(@events)
    source_client_side_setup_data
  end
  def client_setup_prefix_stage_observation
    record = markdown_link_stage_observation
    raise 'client setup tag builder not acquired' unless @setup_builder_acquired
    record[:client_setup_prefix] = {builder_warm_identity: true, builder_owned: true, inputs: ClientSetupReadBootstrap.inputs}
    record
  end
end
class ListBodyContext
  include ClientSetupBuilderSource
  include ClientSetupPrefixSource
  include ClientSetupPrefixViewProtocol
  def setup_builder_owned?(value); value.is_a?(ClientSetupTagBuilder) && value.owned_by?(self); end
  def observation; client_setup_prefix_stage_observation; end
end
