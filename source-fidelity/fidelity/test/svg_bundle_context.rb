# frozen_string_literal: true
require_relative 'svg_bundle_declarations'
require_relative 'svg_bundle_transport'
require_relative 'svg_bundle_bulk_source'
require_relative 'svg_xml_backend'
require_relative 'svg_sprite_read_component'
require_relative 'svg_bundle_source'
module SvgBundleBootstrap
  def self.backend
    unless @backend
      path = ENV.fetch('FIDELITY_SVG_XML_LIBRARY')
      expected = ENV.fetch('FIDELITY_SVG_XML_LIBRARY_SHA256')
      expected += '-wrong' if ENV.fetch('FIDELITY_SVG_BUNDLE_FAULT', '') == 'wrong-library'
      raise ArgumentError, 'SVG XML library provenance changed' unless File.realpath(path) == path && !File.symlink?(path) && Digest::SHA256.hexdigest(File.read(path)) == expected
      @backend = SvgXmlSymbolsBackend.new(path)
    end
    @backend
  end
  def self.read_svg(path)
    root = RequestAssetCapability::ROOT
    RequestAssetServing.verified_member!(root, path)
    value = File.read(path)
    @files ||= {}
    @files[path.delete_prefix(root + '/')] = Digest::SHA256.hexdigest(value)
    value
  end
  def self.files; @files || {}; end
  def self.symbols_for(filename, source, strict:)
    raw = backend.symbols_for(filename, source, strict: strict)
    value = raw
    if ENV.fetch('FIDELITY_SVG_BUNDLE_FAULT', '') == 'wrong-symbol' && !raw.empty?
      value = raw.dup
      key = raw.keys.first
      value[key] = value[key] + '-wrong'
    end
    raise 'SVG XML engine result changed' unless value == raw
    value
  end
  def self.note_theme_query
    @theme_queries = theme_queries + 1
    nil
  end
  def self.theme_queries; @theme_queries || 0; end
  def self.path; @path; end
  def self.version_hit_on_entry; @version_hit_on_entry; end
  def self.source_path(id); RequestSvgSource.path(id); end
  def self.source_bundle(id); RequestSvgSource.bundle(id); end
  def self.source_version(id); RequestSvgSource.version(id); end
  def self.source_icons(id); RequestSvgSource.all_icons(id); end
  def self.source_core; RequestSvgSource.core_svgs; end
  def self.source_custom(id); RequestSvgSource.custom_svgs(id); end
  def self.acquire_path(id)
    SvgIconProducers.note_entry
    key = "version_#{ListThemeCompilerSource.transform_ids(id).join(',')}"
    @version_hit_on_entry = CategoryCacheBootstrap.svg_cache.svg_values.key?(key)
    @path = source_path(id)
    raise HtmlRenderingBoundary, 'actual SVG XML bundle/version/path acquired; client setup/meta serialization pending'
  end
  def self.engine_stats
    @backend.nil? ? {calls: 0, active_documents: 0, original_nokogiri: true} : {calls: @backend.calls, active_documents: @backend.active_documents, original_nokogiri: false}
  end
end
module RequestSvgBootstrap
  def self.path(id); SvgBundleBootstrap.acquire_path(id); end
end
module SvgCacheViewProtocol
  def expected_body_events
    values = expected_client_highlight_events + ['svg_cache_version_acquisition']
    unless SvgBundleBootstrap.version_hit_on_entry
      values += ['svg_cache_icons_acquisition', 'svg_cache_settings_acquisition', 'svg_settings_hash_acquisition']
    end
    values
  end
  def svg_cache_stage_observation
    record = client_highlight_stage_observation
    ids = ListThemeCompilerSource.transform_ids(theme_id)
    id_key = ids.join(',')
    keys = %w[settings_icons badge_icons group_icons] + ["icons_#{id_key}", "version_#{id_key}"] + ids.map { |id| "theme_svg_sprites_#{id}" }
    cache = CategoryCacheBootstrap.svg_cache
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until keys.all? { |key| cache.svg_values.key?(key) }
      raise 'SVG bundle cache publications missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    values = cache.svg_values
    raise 'SVG complete cache keys changed' unless values.keys.sort == keys.sort
    before = CategoryCacheBootstrap.lease.publication_count
    before_queries = SvgBundleBootstrap.theme_queries
    RequestSvgBootstrap.bind([])
    begin
      settings = SvgIconProducers.source_settings_icons
      badges = SvgIconProducers.source_badge_icons
      groups = SvgIconProducers.source_group_icons
      bundle = SvgBundleBootstrap.source_bundle(theme_id)
      version = SvgBundleBootstrap.source_version(theme_id)
    ensure
      RequestSvgBootstrap.bind(@events)
    end
    raise 'SVG settings producer source input changed' unless settings == SvgIconProducers.expected_settings_icons
    raise 'SVG settings producer warm identity changed' unless settings.equal?(values['settings_icons'])
    raise 'SVG badge producer warm identity changed' unless badges.equal?(values['badge_icons'])
    raise 'SVG group producer warm identity changed' unless groups.equal?(values['group_icons'])
    raise 'SVG warm nil sprite cache recomputed' unless before_queries == SvgBundleBootstrap.theme_queries
    raise 'SVG warm bundle republished' unless before == CategoryCacheBootstrap.lease.publication_count
    raise 'SVG badge actual readonly rows changed' unless badges == Badge.pluck(:icon).uniq
    raise 'SVG group actual readonly rows changed' unless groups == Group.pluck(:flair_icon).uniq
    raise 'SVG bundle digest changed' unless version == Digest::SHA1.hexdigest(bundle)
    raise 'SVG path changed' unless SvgBundleBootstrap.path == "/svg-sprite/#{Discourse.current_hostname}/svg-#{theme_id}-#{version}.js"
    icons = values["icons_#{id_key}"]
    raise 'SVG source default icon missing' unless (SvgBundleDeclarations::READ_ICON_SET.to_a - icons).empty?
    raise 'SVG icon order/type changed' unless icons.is_a?(Array) && icons.all? { |item| item.is_a?(String) } && icons == icons.uniq.sort
    core = SvgBundleBootstrap.source_core
    raise 'SVG core source memo identity changed' unless core.equal?(SvgBundleBootstrap.source_core)
    raise 'SVG custom source result not acquired' unless SvgBundleBootstrap.source_custom(theme_id).is_a?(Hash)
    notes = RequestSvgBootstrap.notes
    cold = ["version_#{id_key}:miss", "icons_#{id_key}:miss", 'settings_icons:miss', 'badge_icons:miss', 'group_icons:miss', 'settings_icons:hit', 'badge_icons:hit', 'group_icons:hit', "icons_#{id_key}:hit", "version_#{id_key}:hit"]
    warm = ["version_#{id_key}:hit", 'settings_icons:hit', 'badge_icons:hit', 'group_icons:hit', "icons_#{id_key}:hit", "version_#{id_key}:hit"]
    raise 'SVG complete source cache order changed' unless notes == cold || notes == cold + warm
    raise 'SVG cache manager registration missing' unless CategoryCacheBootstrap.manager.subscribers.size == 5
    record[:svg_cache] = {notes: notes, values: values, registered: true, source_getter_returned: true}
    record[:svg_bundle] = {path: SvgBundleBootstrap.path, version: version, bundle_sha256: Digest::SHA256.hexdigest(bundle), bundle_bytes: bundle.bytesize, icon_count: icons.size, core_symbol_count: core.size, files: SvgBundleBootstrap.files, warm_core_identity: true, warm_nil_sprite_recomputed: false, source_path_returned: true}
    puts 'FIDELITY_SVG_XML_LIFECYCLE ' + JSON.generate(SvgBundleBootstrap.engine_stats)
    record
  end
end
module SvgBundleViewProtocol
  def svg_bundle_stage_observation; svg_theme_icons_stage_observation; end
end
class ListBodyContext
  include SvgBundleViewProtocol
  def observation; svg_bundle_stage_observation; end
end
