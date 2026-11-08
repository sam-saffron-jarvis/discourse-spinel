# frozen_string_literal: true
require_relative 'svg_settings_declarations'
module SiteSettings
  class PortableReadStore
    def svg_definition(name); @definitions[name]; end
    def svg_definitions; @definitions.values; end
    def svg_source_current(site)
      refresh!(site) unless @mutex.synchronize { @values.key?(site) }
      @mutex.synchronize { @values[site] }
    end
    def svg_shadowed?(name, site)
      svg_source_current(site)
      @mutex.synchronize { @shadows[site].include?(name) }
    end
  end
end
module SvgSettingsRead
  def self.bind
    raise ArgumentError, 'unsupported SVG settings loaded plugins' unless Discourse.plugins.empty?
    # The current no-loaded-plugin registry has no default modifiers. This is
    # an admission guard, NOT a replacement modifier result or settings boot.
    raise ArgumentError, 'unsupported SVG settings default modifiers' unless DiscoursePluginRegistry.instance_variable_get(:@modifiers).nil?
    @records = {}
    @pending = nil
    nil
  end
  def self.definitions; SiteSetting.portable_store.svg_definitions; end
  def self.names; definitions.reject { |d| d.name == 'default_locale' }.map(&:name); end
  def self.definition(name)
    value = SiteSetting.portable_store.svg_definition(name)
    raise ArgumentError, 'unknown SVG source setting' if value.nil?
    value
  end
  def self.themeable?(name); definition(name).themeable?; end
  def self.legacy_getters_supported?; false; end
  def self.additional_kind(name); nil; end
  def self.kind(name)
    value = definition(name)
    return 'unsupported' if (SvgSettingsDeclarations::DEPRECATED.include?(name) && !legacy_getters_supported?) || value.options.key?('plugin') || SiteSetting.portable_store.svg_shadowed?(name, SiteSetting.portable_site)
    additional = additional_kind(name)
    return additional unless additional.nil?
    return 'scalar' if value.portable_scalar?
    options = value.options
    return 'upload' if value.data_type == 18 && !value.themeable? && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('portable_source_override')
    'unsupported'
  end
  def self.pending(name)
    @pending = name
    raise HtmlRenderingBoundary, "actual SVG settings_hash prefix acquired; source getter #{name} acquisition pending"
  end
  def self.upload(name)
    key = SiteSetting.portable_site + ':' + name
    @uploads ||= {}
    value = @uploads[key]
    return value unless value.nil?
    id = SiteSetting.portable_store.get_upload_id(name, SiteSetting.portable_site)
    if id != Upload::SEEDED_ID_THRESHOLD
      value = Upload.find_by(id: id)
      @uploads[key] = value unless value.nil?
      value
    end
  end
  def self.read(name)
    branch = kind(name)
    if branch == 'scalar'
      store = SiteSetting.portable_store
      site = SiteSetting.portable_site
      store.refresh!(site) if store.svg_source_current(site)[name].nil?
      store.get(name, site).to_s
    elsif branch == 'upload'
      value = upload(name)
      text = value.nil? ? '' : value.to_s
      text = '' if ENV.fetch('FIDELITY_SVG_SETTINGS_FAULT', '') == 'wrong-upload'
      expected = value.nil? ? '' : value.url
      raise 'SVG upload getter Stringification changed' unless text == expected
      text
    else
      pending(name)
    end
  end
  def self.record(name, text)
    raise TypeError, 'SVG settings_hash value is not String' unless text.is_a?(String)
    @records ||= {}
    @records[name] = definition(name).secret? ? '[secret-not-recorded]' : Digest::SHA256.hexdigest(text)
    text
  end
  def self.records; @records ||= {}; end
  def self.pending_name; @pending; end
  def self.settings_hash
    bind
    result = {}
    keys = names
    keys = keys.drop(1) if ENV.fetch('FIDELITY_SVG_SETTINGS_FAULT', '') == 'drop-setting'
    keys = keys.reverse if ENV.fetch('FIDELITY_SVG_SETTINGS_FAULT', '') == 'reverse-setting-order'
    keys.each do |name|
      next if themeable?(name)
      result[name.to_sym] = record(name, read(name))
    end
    raise 'SVG settings_hash unexpectedly complete without supported full getter contract'
  end
end
module RequestSvgBootstrap
  def self.settings_hash
    events = @events
    raise 'SVG events not bound' unless events.is_a?(Array)
    events << 'svg_settings_hash_acquisition'
    SvgSettingsRead.settings_hash
  end
end
module SvgSettingsViewProtocol
  def svg_settings_stage_observation
    record = svg_cache_stage_observation
    pending = SvgSettingsRead.pending_name
    raise 'SVG pending getter not acquired' unless pending.is_a?(String)
    names = SvgSettingsRead.names.reject { |name| SvgSettingsRead.themeable?(name) }
    first_pending = names.find { |name| SvgSettingsRead.kind(name) == 'unsupported' }
    prefix = names.take_while { |name| name != first_pending }
    raise 'SVG settings getter order changed' unless first_pending == pending && SvgSettingsRead.records.keys == prefix
    raise 'SVG settings actual prefix empty' if prefix.empty?
    record[:svg_settings] = {names: prefix, value_digests: SvgSettingsRead.records, pending_getter: pending, key_projection_only: true, full_snapshot_returned: false}
    record
  end
end
class ListBodyContext
  include SvgSettingsViewProtocol
  def observation; svg_settings_stage_observation; end
end
