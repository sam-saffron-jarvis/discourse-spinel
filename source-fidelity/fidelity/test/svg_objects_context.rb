# frozen_string_literal: true
# Actual source objects read: no JSON parsing/schema validation is part of GET.
module SvgObjectsRead
  def self.current
    definition = SvgSettingsRead.definition('dsa_community_rules')
    options = definition.options
    raise ArgumentError, 'unsupported SVG objects declaration' unless definition.data_type == 28 && options['type'] == 'objects' && definition.default_value.is_a?(Array) && definition.default_value.empty? && !definition.themeable? && !options.key?('plugin') && !options.key?('enum') && !options.key?('mandatory_values') && !options.key?('portable_source_override') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)['dsa_community_rules']
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)['dsa_community_rules']
    end
    raise TypeError, 'SVG objects raw result class changed' unless value.is_a?(String) || value.is_a?(Array)
    value
  end
  def self.note(value)
    raise TypeError, 'SVG objects raw result class changed' unless value.is_a?(String) || value.is_a?(Array)
    raise ArgumentError, 'nonempty SVG objects Array profile unsupported' if value.is_a?(Array) && !value.empty?
    raw = current
    raise 'SVG objects raw identity changed' unless value.equal?(raw)
    raise 'SVG objects freeze changed' unless value.frozen? == raw.frozen?
    @result = value
    nil
  end
  def self.result; @result; end
  def self.read
    value = current
    fault = ENV.fetch('FIDELITY_SVG_OBJECTS_FAULT', '')
    value = 12 if fault == 'wrong-type'
    value = value.dup if fault == 'copied-result'
    value = ['unsupported'] if fault == 'nonempty-array'
    note(value)
    text = value.to_s
    # CONTROL stays valid JSON so actual downstream parsing cannot mask the
    # independent exact-to_s observation; this is still an incorrect String.
    text += ' ' if fault == 'wrong-result'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'dsa_community_rules' ? 'acquired_raw_objects' : additional_kind_without_objects(name)
  end
  def self.read(name, warn: true)
    name == 'dsa_community_rules' ? SvgObjectsRead.read : read_without_objects(name, warn: warn)
  end
end
module SvgObjectsViewProtocol
  def svg_objects_stage_observation
    record = svg_experimental_stage_observation
    value = SvgObjectsRead.result
    SvgObjectsRead.note(value)
    digest = Digest::SHA256.hexdigest(value.to_s)
    raise 'SVG objects String consumer changed' unless SvgSettingsRead.records['dsa_community_rules'] == digest
    record[:svg_objects] = {value_class: value.class.name, frozen: value.frozen?, raw_identity: value.equal?(SvgObjectsRead.current), value_digest: digest, parsed_or_validated: false}
    record
  end
end
class ListBodyContext
  include SvgObjectsViewProtocol
  def observation; svg_objects_stage_observation; end
end
