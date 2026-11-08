# frozen_string_literal: true
module OriginalAssetVersionSource
  def self.memoized?; !@assets_digest.nil?; end
  def self.reset_unit_memo!; @assets_digest = nil; end
end
module ClientSetupReadBootstrap
  def self.asset_version
    events = @events
    raise 'client setup events not bound' unless events.is_a?(Array)
    events << 'asset_version_acquisition'
    value = source_assets_digest
    AssetVersionGraphBootstrap.note_returned
    value
  end
  def self.source_assets_digest; OriginalAssetVersionSource.assets_digest; end
  def self.asset_version_memoized?; OriginalAssetVersionSource.memoized?; end
  def self.reset_unit_asset_memo!; OriginalAssetVersionSource.reset_unit_memo!; end
end
class OriginalListBodyContext
  include AssetVersionBusViewProtocol
  def observation; asset_version_bus_stage_observation; end
end
