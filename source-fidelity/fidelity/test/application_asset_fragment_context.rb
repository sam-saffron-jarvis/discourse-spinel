# frozen_string_literal: true
require "json"
require "digest"
# Supplied graph is derived live from the genuine built manifest, not a fake
# EmberAssets lifecycle or captured request state.
class EmberAssets
  def self.script_chunks; @unit_chunks || {}; end
  def self.script_chunks=(value); @unit_chunks = value; end
  def self.import_map; @unit_import_map || {}; end
  def self.import_map=(value); @unit_import_map = value; end
end
class UnitPluginMetadata
  attr_reader :directory_name
  def initialize(directory_name)
    @directory_name = directory_name
  end
end
class UnitLayoutRequest
  attr_reader :env
  def initialize(encoding, cacheable)
    @env = {Middleware::AnonymousCache::CACHEABLE_ENV => cacheable}
    @env["HTTP_ACCEPT_ENCODING"] = encoding if encoding
  end
end
class UnitLayoutResponse
  attr_reader :headers
  def initialize
    @headers = {"Content-Type" => "text/html"}
  end
end
class UnitFragmentPreloader
  attr_reader :reads
  def initialize(values)
    @values = values
    @reads = 0
  end
  def preloaded_data
    @reads += 1
    @values
  end
end
class UnitLayoutAssetHelper < UnitUrlHelper
  include PortableAssetPreloadMethods
  include UnitCspNonceMethod
  include PortableApplicationAssetFragment
  include PortableLayoutPreloadMethods
  include PortableApplicationPreloadFragment
  include PortableImportMapMethods
  attr_reader :asset_chunks, :response
  attr_accessor :asset_preload_links, :application_layout_preloader, :asset_import_map, :unit_theme_assets
  def initialize(settings, paths, encoding, chunks, unit_staff, cacheable)
    super(settings, paths, encoding)
    @asset_chunks = chunks
    @asset_preload_links = nil
    @application_layout_preloader = nil
    @asset_import_map = {}
    @unit_theme_assets = []
    @unit_staff = unit_staff
    @layout_request = UnitLayoutRequest.new(encoding, cacheable)
    @response = UnitLayoutResponse.new
  end
  def request; @layout_request; end
  def controller; self; end
  def theme_js_assets; @unit_theme_assets; end
  def staff?; @unit_staff; end
end
