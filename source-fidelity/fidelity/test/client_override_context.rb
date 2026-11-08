# frozen_string_literal: true
require_relative 'client_override_layout_helpers'
module RequestClientLocaleBootstrap
  class << self; attr_accessor :last_override_script, :override_locale; end
  def self.override_builds; @override_builds ||= 0; end
  def self.override_checks; @override_checks ||= 0; end
  def self.count_override_check!(locale); self.override_locale = locale.to_s; @override_checks = override_checks + 1; end
  def self.record_overrides(value)
    raise TypeError, 'client override output is not String' unless value.is_a?(String)
    self.last_override_script = value
    @override_builds = override_builds + 1
    value
  end
  def self.build_overrides(locale)
    if ENV.fetch('FIDELITY_OVERRIDE_FAULT', '') == 'skip-empty-retry' && override_builds > 0
      return last_override_script.to_s
    end
    current_root = root
    raise 'client locale root is not bound' unless current_root.is_a?(String)
    helper = RequestClientLocaleSource.new(current_root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))
    record_overrides(helper.output_client_overrides(locale))
  end
end
class ExtraLocalesController
  def self.observed_override_cache
    site = CategoryCacheApplication::RailsMultisite::ConnectionManagement.current_db
    site_js_digests.fetch(site)
  end
  def self.client_overrides_exist?(locale: I18n.locale)
    RequestClientLocaleBootstrap.count_override_check!(locale)
    ActiveSupport.present?(bundle_js_hash(OVERRIDES_BUNDLE, locale: locale))
  end
end
module ClientOverrideViewProtocol
  include ClientOverrideLayoutHelpers
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides', 'theme_translations_acquisition']
  end
  def theme_translations_lookup
    @events << 'theme_translations_acquisition'
    raise HtmlRenderingBoundary, 'actual main/MF/override bundle lifecycle acquired; Theme translation bulk cache acquisition pending'
  end
  def client_override_stage_observation
    record = messageformat_stage_observation
    script = RequestClientLocaleBootstrap.last_override_script
    raise 'client override script was not acquired' unless script.is_a?(String)
    # This proof explicitly admits the observed empty override profile only.
    # Never replace the actual query/helper result with a supplied empty map.
    raise ArgumentError, 'nonempty client override preload profile requires expanded acceptance' unless script.empty?
    builds = RequestClientLocaleBootstrap.override_builds
    checks = RequestClientLocaleBootstrap.override_checks
    raise 'empty override nil cache lifetime violated' unless builds == checks
    cache = ExtraLocalesController.observed_override_cache
    locale = RequestClientLocaleBootstrap.override_locale
    raise 'actual override request locale missing' unless locale.is_a?(String)
    key = 'overrides_' + locale
    raise 'original nil digest cache entry missing' unless cache.key?(key)
    digest_cached = !cache[key].nil?
    raise 'empty override digest must be nil' if digest_cached
    record[:client_overrides] = {bytes: script.bytesize, sha256: Digest::SHA256.hexdigest(script), builds: builds, checks: checks, digest_cached: digest_cached, nil_entry_present: cache.key?(key)}
    record
  end
end
class ListBodyContext
  include ClientOverrideViewProtocol
  def observation; client_override_stage_observation; end
end
