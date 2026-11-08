# frozen_string_literal: true
require_relative 'original_asset_version_graph_source'
module ClientSetupReadBootstrap
  def self.asset_version
    events = @events
    raise 'client setup events not bound' unless events.is_a?(Array)
    events << 'asset_version_acquisition'
    OriginalAssetVersionSource.assets_digest
  end
end
class OriginalListBodyContext
  include AssetVersionGraphViewProtocol
  def observation; asset_version_graph_stage_observation; end
end
