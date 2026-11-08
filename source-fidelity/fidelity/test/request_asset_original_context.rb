# frozen_string_literal: true
require_relative 'list_layout_original_context'
require_relative 'list_compiler_original_context'
require_relative 'original_theme_array_context'
require_relative 'original_request_asset_helpers'
module OriginalRequestAssetProtocol
  def acquire_request_asset_bindings
    raise ArgumentError, 'unsupported loaded request asset plugins' unless Discourse.plugins.empty?
    @asset_source_root = RequestAssetServing.verified_root
    @asset_settings = RequestAssetSettings.new(ListHeadImages.configuration)
    @request_assets = OriginalRequestEmberAssets.new(@asset_source_root, nil)
    compilers = Propshaft::Compilers.new(nil)
    compilers.register('text/javascript', Propshaft::Compiler::SourceMappingUrls)
    @asset_load_path = Propshaft::LoadPath.new(RequestAssetSource.paths(@asset_source_root), compilers: compilers, version: RequestAssetSource.version(@asset_settings))
    resolver = Propshaft::Resolver::Dynamic.new(load_path: @asset_load_path, prefix: '/assets')
    @asset_paths = OriginalRequestAssetView.new(resolver, @asset_settings)
    OriginalRequestAssetBindings.view = @asset_paths
    OriginalRequestAssetBindings.settings = @asset_settings
    @asset_urls = {}
  end
  def theme_js_assets
    @events << 'theme_compiler_version_acquisition'
    OriginalCompilerHelpers.instance_method(:theme_js_assets).bind(self).call
  end
end
class OriginalListBodyContext
  include OriginalRequestAssetHelpers
  include RequestAssetViewProtocol
  include OriginalRequestAssetProtocol
  def observation; asset_stage_observation; end
end
