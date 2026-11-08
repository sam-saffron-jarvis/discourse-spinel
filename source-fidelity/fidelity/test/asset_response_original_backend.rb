# frozen_string_literal: true
# Exact original Propshaft server/compilers in a UNIT Rack context; no listener.
require "pathname"
require "set"
require "rack"
require "propshaft"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/string/access"
raise "unsupported original Rack header version" unless Rack::RELEASE == "2.2.24"
class UnitAssetResponseConfig
  attr_reader :sweep_cache
  def initialize(sweep_cache)
    @sweep_cache = sweep_cache
  end
end
class UnitAssetResponseAssembly
  attr_reader :load_path, :config, :prefix
  def initialize(load_path, sweep_cache)
    @load_path = load_path
    @config = UnitAssetResponseConfig.new(sweep_cache)
    @prefix = "/assets/"
  end
end

def new_unit_asset_response(app, roots, version, sweep_cache = false, watcher_profile = "none")
  raise "unsupported unit original watcher" if sweep_cache && watcher_profile != "null"
  compilers = Propshaft::Compilers.new(nil)
  compilers.register("text/javascript", Propshaft::Compiler::SourceMappingUrls)
  load_path = Propshaft::LoadPath.new(roots, compilers: compilers, version: version)
  Propshaft::Server.new(app, UnitAssetResponseAssembly.new(load_path, sweep_cache))
end
