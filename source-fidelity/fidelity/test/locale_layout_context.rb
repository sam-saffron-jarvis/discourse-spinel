# frozen_string_literal: true
require_relative 'client_locale_registry'
require_relative 'request_client_locale_source'
require_relative 'request_extra_locale_source'
require_relative 'request_locale_layout_helpers'
require_relative 'native_locale_layout'
class HtmlStageObservedController
  attr_accessor :asset_preload_links
end
module RequestClientLocaleBootstrap
  class << self
    attr_accessor :root, :last_main_script
    attr_writer :main_builds, :events
  end
  def self.events
    value = @events
    raise 'locale observer is not bound' unless value.is_a?(Array)
    value
  end
  def self.main_builds; @main_builds ||= 0; end
  def self.date_overrides; @date_overrides ||= {}; end
  def self.bind(root, events)
    raise ArgumentError, 'locale cached source root changed' unless self.root.nil? || self.root == root
    self.root = root
    self.events = events
    # Translation helper ownership is local to the actual shared-cache miss.
    # Original ExtraLocales digest caches still govern genuine warm hits.
    date_overrides
    main_builds
  end
  def self.overrides(locale)
    name = locale.to_s
    return date_overrides[name] if date_overrides.key?(name)
    values = {}
    unless ENV['DISABLE_TRANSLATION_OVERRIDES'] == '1'
      # Exact translate_accelerator.rb read; deprecated rows are NOT filtered
      # here because the actual source does not filter them in this read.
      TranslationOverride.where(locale: name).pluck(:translation_key, :value).each do |row|
        key = row[0]
        value = row[1]
        raise TypeError, 'translation override row is not String/String' unless key.is_a?(String) && value.is_a?(String)
        values[key] = value
      end
    end
    date_overrides[name] = values
  end
  def self.date_translation(name)
    key = 'dates.' + name
    value = overrides(I18n.locale)[key] || I18n.translate_runtime(key, {}, '', false, true)
    raise TypeError, 'live client date input is not String' unless value.is_a?(String)
    value
  end
  def self.build_main(locale)
    current_root = root
    raise 'client locale root is not bound' unless current_root.is_a?(String)
    locale_helper = RequestClientLocaleSource.new(current_root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))
    raise 'client locale source is not bound' unless locale_helper.is_a?(RequestClientLocaleSource)
    result = locale_helper.output_locale(locale)
    raise TypeError, 'client locale output is not String' unless result.is_a?(String)
    self.last_main_script = result
    self.main_builds = main_builds + 1
    result
  end
end
class RequestClientLocaleSource
  # The standalone YAML date driver is NOT used in the request. Bind the
  # actual existing I18n source input and fresh read-only override rows.
  def date_translation(name); RequestClientLocaleBootstrap.date_translation(name); end
  def load_client_yaml(path)
    RequestAssetServing.verified_member!(@root, path)
    data = File.read(path)
    raise TypeError, 'client YAML input is not String' unless data.is_a?(String)
    parsed = YAML.load(data, filename: path)
    raise TypeError, 'client YAML root is not Hash' unless parsed.is_a?(Hash)
    # Only locale ROOT keys are String. Nested YAML maps genuinely contain
    # Boolean/Integer keys; preserve those boxed values without retyping them.
    result = {}
    parsed.each do |key, value|
      raise TypeError, 'client YAML locale root key is not String' unless key.is_a?(String)
      result[key] = value
    end
    result
  end
  def read_client_source(path)
    RequestAssetServing.verified_member!(@root, path)
    File.read(path)
  end
end
module RequestLocaleLayoutProtocol
  def acquire_request_asset_bindings
    acquire_base_request_asset_bindings
    RequestClientLocaleBootstrap.bind(@asset_source_root, @events)
  end
  def bfcache_compatibility_mode?
    value = controller.bfcache_compatibility_mode?
    raise TypeError, 'BFCache decision is not Boolean' unless value == true || value == false
    @bfcache_decision = value
    value
  end
  def render(name = nil, partial: nil, opts: nil)
    unless name == 'layouts/plugin_js'
      raise HtmlRenderingBoundary, 'original early stylesheet preload requires guarded stylesheet effect acquisition' if partial == 'common/discourse_preload_stylesheet'
      raise ArgumentError, 'unknown layout partial' unless partial == 'layouts/head'
      @events << 'layout_head_partial'
      value = capture_list_body { render_head_partial }
      @events << 'layout_head_returned'
      return layout_fragment(value)
    end
    @events << 'layout_importmap_template'
    value = capture_list_body { render_plugin_js_prefix(opts) }
    @incomplete_capture = value.to_s
    @asset_lifecycle_facts = asset_lifecycle_facts
    @events << 'layout_importmap_returned'
    layout_fragment(value)
  end
  def close_request_assets
    return if @request_assets.nil?
    @request_assets.reset unless ENV.fetch('FIDELITY_ASSET_FAULT', '') == 'omitted-reset'
    if !@request_assets.request_cache.nil?
      @request_assets.reset
      raise 'asset request cache cleanup failed; recovered by real reset'
    end
  end
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf']
  end
  def locale_stage_observation
    record = asset_stage_observation
    script = RequestClientLocaleBootstrap.last_main_script
    raise 'main client script was not acquired' unless script.is_a?(String) && !script.empty? && RequestClientLocaleBootstrap.main_builds == 1
    links = controller.asset_preload_links
    raise 'genuine main locale preload missing' unless links.is_a?(Array) && links.size == 1
    digest = ExtraLocalesController.digest_for_content(script)
    raise 'wrong main locale digest/preload' unless record[:layout_prefix].include?('/extra-locales/' + digest + '/') && links.first.include?(digest)
    record[:main_locale] = {bytes: script.bytesize, sha256: Digest::SHA256.hexdigest(script), digest: digest, builds: RequestClientLocaleBootstrap.main_builds, resource_preload_links: links, date_override_values: RequestClientLocaleBootstrap.date_overrides}
    record[:bfcache_decision] = @bfcache_decision
    record
  end
end
class ListBodyContext
  include RequestLocaleLayoutHelpers
  include RequestLocaleLayoutProtocol
  include NativeLocaleApplicationLayout
  def layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @body_output = +''
    @output_buffer = self
    begin
      render_application_layout
      raise 'locale layout prefix unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def observation; locale_stage_observation; end
end
