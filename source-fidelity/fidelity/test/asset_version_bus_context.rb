# frozen_string_literal: true
require_relative 'asset_version_bus_source'
module AssetVersionGraphBootstrap
  def self.last_message(channel)
    raise ArgumentError, 'asset-version MessageBus channel changed' unless channel == '/global/asset-version'
    events = @events
    raise 'asset-version events not bound' unless events.is_a?(Array)
    events << 'asset_version_last_message_acquisition'
    value = CategoryCacheBootstrap.bus.last_message(channel)
    ENV.fetch('FIDELITY_ASSET_BUS_FAULT', '') == 'redundant-publication' ? nil : value
  end
  def self.publish(channel, value)
    return nil if ENV.fetch('FIDELITY_ASSET_BUS_FAULT', '') == 'missing-publication'
    channel += '/wrong' if ENV.fetch('FIDELITY_ASSET_BUS_FAULT', '') == 'wrong-channel'
    value += 'wrong' if ENV.fetch('FIDELITY_ASSET_BUS_FAULT', '') == 'wrong-digest'
    CategoryCacheBootstrap.bus.publish(channel, value)
  end
  def self.computations; @computations || 0; end
  def self.returned; @returned || 0; end
  def self.note_returned
    @returned = returned + 1
    events = @events
    raise 'asset-version events not bound' unless events.is_a?(Array)
    events << 'asset_version_returned'
    nil
  end
end
module RequestAssetVersionSource
  def self.memoized?; !@assets_digest.nil?; end
  def self.reset_unit_memo!; @assets_digest = nil; end
end
module ClientSetupReadBootstrap
  def self.source_assets_digest; RequestAssetVersionSource.assets_digest; end
  def self.asset_version_memoized?; RequestAssetVersionSource.memoized?; end
  def self.reset_unit_asset_memo!; RequestAssetVersionSource.reset_unit_memo!; end
  def self.asset_version
    events = @events
    raise 'client setup events not bound' unless events.is_a?(Array)
    events << 'asset_version_acquisition'
    value = source_assets_digest
    AssetVersionGraphBootstrap.note_returned
    value
  end
end
module AssetVersionBusViewProtocol
  def expected_body_events
    prefix = ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition', 'view_flow_receiver', 'layout_head_yield_returned', 'markdown_alternate_acquisition', 'markdown_alternate_returned', 'client_setup_tag_acquisition', 'client_setup_tag_returned', 'client_setup_data_acquisition', 'asset_version_acquisition']
    prefix += ['asset_version_graph_acquisition', 'asset_version_last_message_acquisition'] unless @asset_version_was_memoized
    prefix + ['asset_version_returned', 'loading_admin_acquisition']
  end
  def client_side_setup_data
    @events << 'client_setup_data_acquisition'
    raise 'client setup evaluated before actual tag receiver' unless @setup_builder_acquired
    if ENV.fetch('FIDELITY_ASSET_BUS_UNIT_RESET', '') == '1' && AssetVersionGraphBootstrap.returned > 0
      ClientSetupReadBootstrap.reset_unit_asset_memo!
    end
    @asset_version_was_memoized = ClientSetupReadBootstrap.asset_version_memoized?
    ClientSetupReadBootstrap.begin_request(@events)
    AssetVersionGraphBootstrap.bind(@asset_load_path, @asset_source_root, @events)
    source_client_side_setup_data
  end
  def loading_admin?
    @events << 'loading_admin_acquisition'
    raise HtmlRenderingBoundary, 'actual asset-version lifecycle acquired; client setup remaining inputs acquisition pending'
  end
  def asset_version_bus_stage_observation
    record = asset_version_graph_stage_observation
    value = ClientSetupReadBootstrap.inputs[:asset_version]
    raise 'asset-version source return not acquired' unless value.is_a?(String) && value == AssetVersionGraphBootstrap.digest
    lease = CategoryCacheBootstrap.lease
    publications = lease.asset_version_publications
    raise 'asset-version publication missing' unless publications > 0
    raise 'asset-version redundant publication' unless publications == 1
    before = lease.asset_version_reads
    warm = ClientSetupReadBootstrap.source_assets_digest
    raise 'asset-version warm memo identity changed' unless warm.equal?(value) && lease.asset_version_reads == before
    message = CategoryCacheBootstrap.bus.last_message('/global/asset-version')
    raise 'asset-version genuine server backlog differs' unless !message.nil? && message.channel == '/global/asset-version' && message.data == value && message.user_ids.nil? && message.group_ids.nil? && message.client_ids.nil?
    record[:asset_version_bus] = {digest: value, publications: publications, source_memo_warm_identity: true, was_memoized: @asset_version_was_memoized, computations: AssetVersionGraphBootstrap.computations, source_reads_before_audit: before, reads_after_audit: lease.asset_version_reads, message_id: message.message_id}
    record
  end
end
class ListBodyContext
  include AssetVersionBusViewProtocol
  def observation; asset_version_bus_stage_observation; end
end
