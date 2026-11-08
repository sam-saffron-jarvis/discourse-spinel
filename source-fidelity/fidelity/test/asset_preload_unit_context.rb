# frozen_string_literal: true
# UNIT/DEPENDENCY context only: supplied URLs, nonces and isolated controller
# preload state. Nothing here represents a request or production configuration.
require "json"
require "digest"
class EmberAssets
  def self.script_chunks
    @script_chunks || {}
  end
  def self.script_chunks=(value)
    @script_chunks = value
  end
end
class UnitAssetContext
  attr_reader :asset_chunks
  attr_accessor :asset_preload_links
  def initialize(chunks, urls, nonce)
    @asset_chunks = chunks
    @urls = urls
    @nonce = nonce
    @asset_preload_links = nil
  end
  def controller
    self
  end
  def script_asset_path(script)
    @urls.fetch(script)
  end
  def csp_nonce_placeholder
    @nonce
  end
end
class UnitAssetHelper < UnitAssetContext
  include PortableAssetPreloadMethods
end
