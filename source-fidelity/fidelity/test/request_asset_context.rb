# frozen_string_literal: true
# Explicit bounded read-only asset capability on the SAME application request.
require_relative 'request_ember_assets'
require_relative 'request_asset_paths_source'
require_relative 'request_asset_helpers'
require_relative 'emitted/runtime/action_view/source_asset_paths'
class RequestAssetSettings
  def initialize(configuration); @configuration = configuration; end
  def string(name)
    value = @configuration.value(name)
    raise TypeError, 'asset configuration is not nullable String' unless value.nil? || value.is_a?(String)
    value
  end
  def relative_url_root; string('relative_url_root'); end
  def cdn_url; string('cdn_url'); end
  def asset_host; cdn_url; end
  def default_asset_host_protocol; nil; end
  def s3_cdn_url; string('s3_cdn_url'); end
  def s3_asset_cdn_url; string('s3_asset_cdn_url'); end
  def asset_url_salt; string('asset_url_salt'); end
  def use_s3?
    # GlobalSetting#use_s3? source's actual credentials predicate. No input map.
    !!(@configuration.value('s3_bucket') && @configuration.value('s3_region') &&
      (@configuration.value('s3_use_iam_profile') ||
      (@configuration.value('s3_access_key_id') && @configuration.value('s3_secret_access_key'))))
  end
end
module RequestAssetServing
  def self.verified_member!(root, path)
    raise ArgumentError, 'asset member escaped acquired root' unless path.start_with?(root + '/') && !path.split('/').include?('..')
    lease = JSON.parse(File.read(ENV.fetch('FIDELITY_ASSET_LEASE')))
    raise ArgumentError, 'asset member root/owner changed' unless lease['root'] == root && lease['owner_pid'] == ENV.fetch('FIDELITY_CACHE_OWNER_PID').to_i
    bytes = File.read(lease['provenance'])
    raise ArgumentError, 'asset serving provenance identity' unless Digest::SHA256.hexdigest(bytes) == RequestAssetCapability::PROVENANCE_SHA256
    provenance = JSON.parse(bytes)
    expected = provenance['files'][path.delete_prefix(root + '/')]
    raise ArgumentError, 'unadmitted or stale resolved asset member' unless expected.is_a?(String) && File.file?(path) && Digest::SHA256.file(path).hexdigest == expected
    true
  end
  def self.verified_root
    lease = JSON.parse(File.read(ENV.fetch('FIDELITY_ASSET_LEASE')))
    raise ArgumentError, 'asset serving lease ownership' unless lease['owner_pid'] == ENV.fetch('FIDELITY_CACHE_OWNER_PID').to_i
    source = File.read(lease['provenance'])
    raise ArgumentError, 'asset serving provenance identity' unless Digest::SHA256.hexdigest(source) == RequestAssetCapability::PROVENANCE_SHA256
    provenance = JSON.parse(source)
    root = lease['root']
    raise ArgumentError, 'wrong asset serving root' unless root.is_a?(String) && root == RequestAssetCapability::ROOT && root == provenance['root'] && provenance['pin'] == RequestAssetCapability::PIN && provenance['graph_or_urls_supplied'] == false
    provenance['files'].each do |relative, expected|
      raise ArgumentError, 'asset serving member traversal' unless relative.is_a?(String) && !relative.start_with?('/') && !relative.split('/').include?('..')
      path = File.join(root, relative)
      raise ArgumentError, 'stale or missing asset serving member' unless File.file?(path) && Digest::SHA256.file(path).hexdigest == expected
    end
    provenance['absent'].each do |relative|
      raise ArgumentError, 'unadmitted asset build status appeared' if File.exist?(File.join(root, relative))
    end
    raise ArgumentError, 'unsupported static Propshaft manifest profile' if File.exist?(File.join(root, 'public/assets/.manifest.json'))
    root
  end
end
module RequestAssetViewProtocol
  def acquire_request_asset_bindings
    raise ArgumentError, 'unsupported loaded request asset plugins' unless Discourse.plugins.empty?
    @asset_source_root = RequestAssetServing.verified_root
    @asset_settings = RequestAssetSettings.new(ListHeadImages.configuration)
    @request_assets = RequestEmberAssets.new(@asset_source_root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))
    @asset_load_path = ActionView::SourceAssetLoadPath.new(RequestAssetSource.paths(@asset_source_root), RequestAssetSource.version(@asset_settings))
    # This owned immutable one-shot lookup is not a null/evented watcher claim.
    @asset_load_path.refresh!
    @asset_paths = ActionView::SourceAssetPaths.new(ActionView::SourceAssetResolver.new(@asset_load_path, '/assets'), @asset_settings.relative_url_root, @asset_settings.cdn_url)
    @asset_urls = {}
  end
  def settings; @asset_settings; end
  def asset_paths; @asset_paths; end
  def request_assets; @request_assets; end
  def theme_js_assets
    @events << 'theme_compiler_version_acquisition'
    ListThemeCompilerSource.js_asset_info(theme_id, skip_transformation: ActiveSupport.present?(request.env['discourse.skip_theme_ids_transformation']))
  end
  def generate_import_map(plugin_assets)
    @events << 'asset_serving_root_acquisition'
    acquire_request_asset_bindings
    value = source_generate_import_map(plugin_assets)
    @returned_import_map = value.to_s
    value
  end
  def script_asset_path(script)
    value = source_script_asset_path(script)
    asset = @asset_load_path.find("#{script}.js")
    raise ArgumentError, 'resolved asset outside acquired serving root' unless asset && asset.path.to_s.start_with?(@asset_source_root + '/')
    RequestAssetServing.verified_member!(@asset_source_root, asset.path.to_s)
    @asset_urls[script] = value
    value
  end
  def asset_lifecycle_facts
    first = request_assets.import_map
    cache = request_assets.cache
    manifest = request_assets.read_manifest!(exception: true)
    raise 'asset import warm identity' unless first.equal?(request_assets.import_map)
    raise 'asset manifest warm identity' unless manifest.equal?(request_assets.read_manifest!(exception: true))
    raise 'asset request cache warm identity' unless cache.equal?(request_assets.cache)
    {warm_import_identity: true, warm_manifest_identity: true, warm_request_cache_identity: true}
  end
  def render(name = nil, partial: nil, opts: nil)
    unless name == 'layouts/plugin_js'
      # Explicit existing scoped layout adapter, rather than another ambiguous
      # same-name mixin super chain. No original template/helper branch changes.
      raise HtmlRenderingBoundary, 'original early stylesheet preload requires guarded stylesheet effect acquisition' if partial == 'common/discourse_preload_stylesheet'
      raise ArgumentError, 'unknown layout partial' unless partial == 'layouts/head'
      @events << 'layout_head_partial'
      value = capture_list_body { render_head_partial }
      @events << 'layout_head_returned'
      return layout_fragment(value)
    end
    @events << 'layout_importmap_template'
    begin
      value = capture_list_body { render_plugin_js_prefix(opts) }
      @incomplete_capture = value.to_s
      @asset_lifecycle_facts = asset_lifecycle_facts
      @events << 'layout_importmap_returned'
      raise HtmlRenderingBoundary, 'actual import-map partial returned from acquired asset graph; remaining core layout preloads pending'
    ensure
      unless @request_assets.nil?
        @request_assets.reset
        raise 'asset request cache cleanup failed' unless @request_assets.request_cache.nil?
      end
    end
  end
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned']
  end
  def asset_stage_observation
    record = compiler_stage_observation
    raise 'asset request cleanup missing' unless request_assets.request_cache.nil?
    record[:asset_serving_root] = @asset_source_root
    record[:asset_urls] = @asset_urls
    record[:returned_import_map] = @returned_import_map
    record[:asset_lifecycle] = @asset_lifecycle_facts
    record[:asset_request_reset] = true
    record[:import_map_returned] = true
    record
  end
end
class ListBodyContext
  include RequestAssetHelpers
  include RequestAssetViewProtocol
  def observation; asset_stage_observation; end
end
