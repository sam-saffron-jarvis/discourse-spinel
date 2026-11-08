# frozen_string_literal: true
require_relative 'asset_version_graph_source'
module AssetVersionGraphBootstrap
  def self.bind(load_path, root, events)
    lease = CategoryCacheBootstrap.lease
    lease.check!(lease.host, lease.port)
    raise ArgumentError, 'asset-version serving-root changed' unless root == RequestAssetCapability::ROOT
    @load_path = load_path
    @root = root
    @events = events
    @graph = []
    @digest = nil
    nil
  end
  def self.graph; @graph ||= []; end
  def self.digest; @digest; end
  def self.verified_load_path
    path = @load_path
    root = @root
    events = @events
    raise 'asset-version graph not bound' if path.nil? || !root.is_a?(String) || !events.is_a?(Array)
    events << 'asset_version_graph_acquisition'
    rows = []
    path.assets.each do |asset|
      RequestAssetServing.verified_member!(root, asset.path.to_s)
      rows << {logical_path: asset.logical_path.to_s, digested_path: asset.digested_path.to_s}
    end
    raise 'empty acquired asset-version graph' if rows.empty?
    @graph = rows.sort_by { |row| row[:logical_path] }
    path
  end
  def self.assets
    path = verified_load_path
    values = path.assets
    ENV.fetch('FIDELITY_ASSET_VERSION_FAULT', '') == 'drop-member' ? values.drop(1) : values
  end
  def self.note_digest(value)
    expected = Digest::MD5.hexdigest(graph.map { |row| row[:digested_path] }.sort.join('|'))
    raise 'asset version digest does not cover full acquired graph' unless value == expected
    @digest = value
    nil
  end
  def self.last_message(channel)
    raise ArgumentError, 'asset-version MessageBus channel changed' unless channel == '/global/asset-version'
    events = @events
    raise 'asset-version events not bound' unless events.is_a?(Array)
    events << 'asset_version_last_message_acquisition'
    raise HtmlRenderingBoundary, 'actual full asset-version graph/digest acquired; original MessageBus last-message/publication lifecycle acquisition pending'
  end
  def self.publish(channel, value); raise ArgumentError, 'asset-version publication acquisition pending'; end
end
module ClientSetupReadBootstrap
  def self.asset_version
    events = @events
    raise 'client setup events not bound' unless events.is_a?(Array)
    events << 'asset_version_acquisition'
    RequestAssetVersionSource.assets_digest
  end
end
module AssetVersionGraphViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition', 'theme_translations_returned', 'core_browser_detect_acquisition', 'core_browser_detect_returned', 'core_module_preloads_acquisition', 'core_module_preloads_returned', 'theme_compiler_version_acquisition', 'theme_head_tag_acquisition', 'theme_head_tag_returned', 'analytics_head_acquisition', 'analytics_google_universal_acquisition', 'analytics_adobe_acquisition', 'manifest_url_acquisition', 'ios_banner_acquisition', 'layout_head_yield_acquisition', 'view_flow_receiver', 'layout_head_yield_returned', 'markdown_alternate_acquisition', 'markdown_alternate_returned', 'client_setup_tag_acquisition', 'client_setup_tag_returned', 'client_setup_data_acquisition', 'asset_version_acquisition', 'asset_version_graph_acquisition', 'asset_version_last_message_acquisition']
  end
  def client_side_setup_data
    @events << 'client_setup_data_acquisition'
    raise 'client setup evaluated before actual tag receiver' unless @setup_builder_acquired
    ClientSetupReadBootstrap.begin_request(@events)
    AssetVersionGraphBootstrap.bind(@asset_load_path, @asset_source_root, @events)
    source_client_side_setup_data
  end
  def asset_version_graph_stage_observation
    record = client_setup_prefix_stage_observation
    digest = AssetVersionGraphBootstrap.digest
    graph = AssetVersionGraphBootstrap.graph
    raise 'asset-version graph/digest not acquired' unless digest.is_a?(String) && !graph.empty?
    record[:asset_version_graph] = {digest: digest, assets: graph, asset_count: graph.size, message_bus_dispatched: false}
    record
  end
end
class ListBodyContext
  include AssetVersionGraphViewProtocol
  def observation; asset_version_graph_stage_observation; end
end
