# frozen_string_literal: true
# Isolated original framework objects, NOT a Rails application boot.
require "pathname"
require "set"
require "propshaft"
require "action_view"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/string/access"
require "fast_blank"
module Rails
  class << self
    attr_accessor :unit_assets
    def application
      self
    end
    def assets
      unit_assets
    end
  end
end
class UnitOriginalAssetAssembly
  attr_reader :resolver
  def initialize(resolver)
    @resolver = resolver
  end
end
class UnitOriginalAssetView
  include ActionView::Helpers::AssetUrlHelper
  include Propshaft::Helper
  attr_reader :config
  def initialize(resolver, settings)
    @resolver = resolver
    @config = settings
  end
  def activate
    Rails.unit_assets = UnitOriginalAssetAssembly.new(@resolver)
  end
end
module GlobalSetting
  class << self
    attr_accessor :unit_settings
    def use_s3?; unit_settings.use_s3?; end
    def s3_cdn_url; unit_settings.s3_cdn_url; end
    def s3_asset_cdn_url; unit_settings.s3_asset_cdn_url; end
    def cdn_url; unit_settings.cdn_url; end
  end
end
module ActionController
  class Base
    class << self
      attr_accessor :helpers, :config
    end
  end
end
# Include after UnitUrlHelper is defined by the test context.
module UnitOriginalActivation
  def activate
    asset_paths.activate
    GlobalSetting.unit_settings = settings
    ActionController::Base.helpers = asset_paths
    ActionController::Base.config = settings
  end
  def script_asset_path(script)
    activate
    super
  end
  def asset_cdn_path(path, brotli: false)
    activate
    super
  end
end

def new_unit_url_helper(settings, roots, version, encoding)
  # SourceMappingUrls is the ACTUAL only compiler kept by pinned Discourse.
  # referenced_by is inherited empty Set, not a fake references result.
  compilers = Propshaft::Compilers.new(nil)
  compilers.register("text/javascript", Propshaft::Compiler::SourceMappingUrls)
  load_path = Propshaft::LoadPath.new(roots, compilers: compilers, version: version)
  resolver = Propshaft::Resolver::Dynamic.new(load_path: load_path, prefix: "/assets")
  view = UnitOriginalAssetView.new(resolver, settings)
  helper = UnitOriginalUrlHelper.new(settings, view, encoding)
  helper.activate
  helper
end

def missing_asset_error?(error)
  error.is_a?(Propshaft::MissingAssetError)
end
