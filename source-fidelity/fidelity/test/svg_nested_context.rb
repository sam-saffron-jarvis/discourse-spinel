# frozen_string_literal: true
require_relative 'svg_nested_declarations'
module SvgNestedRead
  def self.supported?(name)
    return false unless SvgNestedDeclarations::SCOPES.key?(name)
    definition = SvgSettingsRead.definition(name)
    options = definition.options
    options['portable_source_override'] == true && [1, 3, 5].include?(definition.data_type) && !definition.themeable? && !options.key?('enum') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('plugin')
  end
  def self.current(name)
    raise ArgumentError, 'unproved SVG top-level generated getter scope' unless supported?(name)
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)[name]
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)[name]
    end
    mandatory = SvgSettingsRead.definition(name).options['mandatory_values']
    value = (mandatory.split('|') | value.to_s.split('|')).join('|') if mandatory.is_a?(String)
    value
  end
  def self.read(name)
    value = current(name)
    value = [value] if ENV.fetch('FIDELITY_SVG_NESTED_FAULT', '') == 'wrong-type'
    type = SvgSettingsRead.definition(name).data_type
    valid = (type == 1 && value.is_a?(String)) || (type == 3 && value.is_a?(Integer)) || (type == 5 && (value == true || value == false))
    raise TypeError, 'SVG generated scalar getter raw type changed' unless valid
    text = value.to_s
    text += '-wrong' if ENV.fetch('FIDELITY_SVG_NESTED_FAULT', '') == 'wrong-value'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    SvgNestedRead.supported?(name) ? 'lexical_generated_scalar' : additional_kind_without_nested(name)
  end
  def self.read(name, warn: true)
    SvgNestedRead.supported?(name) ? SvgNestedRead.read(name) : read_without_nested(name, warn: warn)
  end
end
module SvgNestedViewProtocol
  def svg_nested_stage_observation
    record = svg_choice_list_stage_observation
    values = {}
    SvgSettingsRead.records.each do |name, digest|
      next unless SvgNestedRead.supported?(name)
      value = SvgNestedRead.current(name)
      raise 'SVG generated scalar getter value changed' unless digest == Digest::SHA256.hexdigest(value.to_s)
      values[name] = {raw_class: value.class.name, nested_helper_owner_not_invoked: SvgNestedDeclarations::SCOPES[name]}
    end
    raise 'SVG top-level enable_s3_uploads getter not reached' unless values.key?('enable_s3_uploads')
    record[:svg_lexical_getters] = values
    record
  end
end
class ListBodyContext
  include SvgNestedViewProtocol
  def observation; svg_nested_stage_observation; end
end
