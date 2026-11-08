# frozen_string_literal: true
require_relative "layout_asset_processor_backend"
require_relative "list_compiler_source"
module LayoutAssetProcessorVM
  class << self; attr_accessor :backend; end
  def self.ember_version
    CategoryCacheBootstrap.lease.check!(CategoryCacheBootstrap.lease.host, CategoryCacheBootstrap.lease.port)
    if backend.nil?
      root = ENV.fetch("FIDELITY_VM_SOURCE_ROOT")
      metadata = JSON.parse(File.read(File.join(root, "vm-source-lease.json")))
      owner = metadata["owner_pid"]
      owner += 1 if ENV.fetch("FIDELITY_COMPILER_FAULT", "") == "wrong-vm-owner"
      raise "VM source fixture ownership" unless owner == ENV.fetch("FIDELITY_CACHE_OWNER_PID").to_i && metadata["generated_version_supplied"] == false
      metadata["files"].each do |relative, expected|
        raise "VM source traversal" if relative.start_with?("/") || relative.split("/").include?("..")
        raise "VM source fixture bytes changed" unless Digest::SHA256.file(File.join(root, relative)).hexdigest == expected
      end
      # Existing precompiled cache bytes are an application SOURCE artifact,
      # never an observed version/result supplied by the oracle.
      bundle = metadata["bundle"]
      raise "VM bundle is not an owned verified source member" unless bundle.is_a?(String) && metadata["files"].key?(bundle) && !bundle.start_with?("/") && !bundle.split("/").include?("..")
      source = File.read(File.join(root, bundle))
      library = ENV.fetch("FIDELITY_VM_LIBRARY")
      raise "VM native library identity" unless Digest::SHA256.file(library).hexdigest == ENV.fetch("FIDELITY_VM_LIBRARY_SHA256")
      mode = ListHeadImages.configuration.value("mini_racer_single_threaded")
      raise "VM configuration type" unless mode == true || mode == false
      self.backend = LayoutAssetProcessorBackend.new(library)
      backend.start(source, mode)
    end
    value = backend.ember_version
    raise TypeError, "AssetProcessor version is not String" unless value.is_a?(String) && !value.empty?
    value
  end
  def self.close
    backend.close unless backend.nil?
    self.backend = nil
  end
end
module ListThemeCompilerSource
  module AssetProcessor
    BASE_COMPILER_VERSION = ListCompilerSource::BASE_COMPILER_VERSION
    def self.ember_version; LayoutAssetProcessorVM.ember_version; end
  end
  module GlobalSetting
    def self.cdn_url; ListHeadImages.configuration.value("cdn_url"); end
    def self.s3_cdn_url; ListHeadImages.configuration.value("s3_cdn_url"); end
    def self.s3_endpoint; ListHeadImages.configuration.value("s3_endpoint"); end
    def self.s3_bucket; ListHeadImages.configuration.value("s3_bucket"); end
  end
  def self.get_set_cache(key)
    if key != "compiler_version"
      raise HtmlRenderingBoundary, "actual source/V8 theme compiler version acquired; Theme extra_js array cache/bake capability pending, not a permission barrier"
    end
    raise "compiler block must use its source-specialized typed call site"
  end
end
require_relative "native_importmap_registry"
require_relative "native_importmap_prefix"
require_relative "importmap_nonce_source"
class ListBodyContext
  include NativeImportMapPrefix
  def csp_nonce_placeholder
    ContentSecurityPolicy.nonce_placeholder(@controller.response.headers, request_env: request.env)
  end
end
module ListCompilerViewProtocol
  def response; @controller.response; end
  def generate_import_map(plugin_assets)
    raise "nonempty scoped importmap plugins" unless plugin_assets.empty? && Discourse.plugins.empty?
    @events << "theme_compiler_version_acquisition"
    ListThemeCompilerSource.js_asset_info(theme_id, skip_transformation: ActiveSupport.present?(request.env["discourse.skip_theme_ids_transformation"]))
  end
  def render(name = nil, partial: nil, opts: nil)
    if name == "layouts/plugin_js"
      @events << "layout_importmap_template"
      capture_list_body { render_plugin_js_prefix(opts) }
      raise "importmap prefix unexpectedly returned"
    else
      super
    end
  end
  def expected_body_events
    ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template", "view_flow_set", "layout_render", "layout_head_partial", "layout_color_cache_acquisition", "layout_head_returned", "layout_importmap_template", "theme_compiler_version_acquisition"]
  end
  def compiler_stage_observation
    record = layout_stage_observation
    nonce = @controller.response.headers[Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER]
    raise "genuine importmap nonce missing" unless nonce.is_a?(String) && /\A[A-Za-z0-9]{25}\z/.match?(nonce) && request.env[Middleware::CspScriptNonceInjector::NONCE_ENV] == nonce
    raise "actual importmap template missing nonce" unless @incomplete_capture.include?('type="importmap" nonce="' + nonce + '"')
    record[:csp_nonce] = nonce
    record
  end
end
class ListBodyContext
  include ListCompilerViewProtocol
  def observation; compiler_stage_observation; end
end
module CategoryCacheBootstrap
  def self.theme_compiler_cache
    return acquired_theme_compiler_cache unless acquired_theme_compiler_cache.nil?
    lease.theme_cache_key = ListCompilerSource::THEME_CACHE_KEY
    self.acquired_theme_compiler_cache = CategoryCacheApplication::DistributedCache.new(ListCompilerSource::THEME_CACHE_KEY, manager: manager)
    raise "compiler cache subscription registration missing" unless bus.backend_instance.subscribed && manager.subscribers.size == 4
    acquired_theme_compiler_cache
  end
  class << self
    alias_method :close_before_vm_driver!, :close!
    def close!
      begin
        close_before_vm_driver!
      ensure
        LayoutAssetProcessorVM.close
      end
    end
  end
end
