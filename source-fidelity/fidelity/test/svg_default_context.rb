# frozen_string_literal: true
require_relative 'svg_default_declarations'
module SiteSettings
  class PortableReadStore
    def svg_change_enabled(name, site, statuses)
      raise ArgumentError, 'unsupported SVG default change' unless SvgDefaultDeclarations::CHANGES.values.include?(name)
      definition = @definitions[name]
      raise PortableUnsupported, 'missing SVG default change declaration' if definition.nil?
      options = definition.options
      metadata = options['upcoming_change']
      raise PortableUnsupported, 'unsupported SVG core default change profile' unless definition.data_type == 5 && !definition.themeable? && metadata.is_a?(Hash) && !options.key?('plugin') && !options.key?('depends_on') && !options.key?('depends_on_values') && !options.key?('upcoming_change_default_override') && !options.key?('portable_source_override')
      svg_source_current(site)
      values = @mutex.synchronize { @values[site] }
      modified = @mutex.synchronize { @modified[site] }
      shadows = @mutex.synchronize { @shadows[site] }
      raise PortableUnsupported, 'unsupported shadowed SVG default change' if shadows.include?(name)
      status = metadata['status'].to_s
      promotion = get('promote_upcoming_changes_on_status', site).to_s
      status_value = statuses[status.to_sym]
      promotion_value = statuses[promotion.to_sym]
      raise PortableUnsupported, 'unknown SVG change status' unless status_value && promotion_value
      value = if modified.key?(name) && status != 'permanent'
        values[name]
      elsif status_value >= promotion_value || status == 'permanent'
        true
      else
        definition.default_value
      end
      value = 'invalid-Boolean' if ENV.fetch('FIDELITY_SVG_DEFAULT_FAULT', '') == 'non-boolean-change'
      raise PortableUnsupported, 'SVG default change is not Boolean' unless value == true || value == false
      value
    end
    def svg_default_value(name, site, statuses)
      definition = @definitions[name]
      raise PortableUnsupported, 'missing SVG default target' if definition.nil?
      options = definition.options
      override = options['upcoming_change_default_override']
      change = SvgDefaultDeclarations::CHANGES[name]
      raise PortableUnsupported, 'unsupported SVG default target profile' unless change.is_a?(String) && override.is_a?(Hash) && override['upcoming_change'] == change && !definition.themeable? && !options.key?('plugin') && !options.key?('portable_source_override') && !options.key?('locale_default') && !options.key?('upcoming_change') && [3, 20].include?(definition.data_type)
      value = svg_source_current(site)[name]
      raise PortableUnsupported, 'unsupported shadowed SVG default target' if svg_shadowed?(name, site)
      enabled = svg_change_enabled(change, site, statuses)
      if !setting_modified_from_default?(name, site)
        value = enabled ? override['new_default'] : definition.default_value
      end
      raise PortableUnsupported, 'SVG default target result type' unless value.is_a?(String) || value.is_a?(Integer)
      value
    end
  end
end
module SvgDefaultRead
  def self.read(name)
    value = SiteSetting.portable_store.svg_default_value(name, SiteSetting.portable_site, HtmlUpcomingStatuses::VALUES)
    text = value.to_s
    text += '-wrong' if ENV.fetch('FIDELITY_SVG_DEFAULT_FAULT', '') == 'wrong-result'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    SvgDefaultDeclarations::CHANGES.key?(name) ? 'acquired_default_target' : additional_kind_without_defaults(name)
  end
  def self.read(name, warn: true)
    SvgDefaultDeclarations::CHANGES.key?(name) ? SvgDefaultRead.read(name) : read_without_defaults(name, warn: warn)
  end
end
module SvgDefaultViewProtocol
  def svg_default_stage_observation
    record = svg_enum_stage_observation
    values = {}
    SvgDefaultDeclarations::CHANGES.each do |name, change|
      next unless SvgSettingsRead.records.key?(name)
      expected = SiteSetting.portable_store.svg_default_value(name, SiteSetting.portable_site, HtmlUpcomingStatuses::VALUES)
      digest = Digest::SHA256.hexdigest(expected.to_s)
      raise 'SVG upcoming default result changed' unless SvgSettingsRead.records[name] == digest
      values[name] = {value_digest: digest, change: change, target_modified: SiteSetting.portable_store.setting_modified_from_default?(name, SiteSetting.portable_site)}
    end
    raise 'SVG whisper default getter not reached' unless values.key?('whispers_allowed_groups')
    record[:svg_defaults] = values
    record
  end
end
class ListBodyContext
  include SvgDefaultViewProtocol
  def observation; svg_default_stage_observation; end
end
