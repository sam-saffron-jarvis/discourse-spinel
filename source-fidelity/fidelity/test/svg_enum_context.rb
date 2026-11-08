# frozen_string_literal: true
require_relative 'svg_enum_declarations'
module SvgEnumRead
  def self.current(name)
    definition = SvgSettingsRead.definition(name)
    options = definition.options
    raise ArgumentError, 'SVG unwrapped enum declaration changed' unless SvgEnumDeclarations::NAMES[name] == options['enum'] && !definition.themeable? && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('portable_source_override')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)[name]
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)[name]
    end
    value
  end
  def self.read(name)
    value = current(name)
    target = ENV.fetch('FIDELITY_SVG_ENUM_TARGET', '')
    fault = target == '' || target == name ? ENV.fetch('FIDELITY_SVG_ENUM_FAULT', '') : ''
    value = ActionView::HtmlFragment.new(value.to_s) if fault == 'wrong-wrapper'
    expected_class = SvgEnumDeclarations::RETURN_CLASSES[name]
    if expected_class == 'Integer'
      raise TypeError, 'SVG unwrapped enum must remain Integer' unless value.is_a?(Integer)
    else
      raise TypeError, 'SVG unwrapped enum must remain String' unless value.is_a?(String)
    end
    text = value.to_s
    text += '-wrong' if fault == 'wrong-value'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    SvgEnumDeclarations::NAMES.key?(name) ? 'enum_unwrapped' : additional_kind_without_enums(name)
  end
  def self.read(name, warn: true)
    SvgEnumDeclarations::NAMES.key?(name) ? SvgEnumRead.read(name) : read_without_enums(name, warn: warn)
  end
end
module SvgEnumViewProtocol
  def svg_enum_stage_observation
    record = svg_top_menu_stage_observation
    types = {}
    SvgEnumDeclarations::NAMES.each do |name, klass|
      next unless SvgSettingsRead.records.key?(name)
      value = SvgEnumRead.current(name)
      expected_class = SvgEnumDeclarations::RETURN_CLASSES[name]
      raise TypeError, 'SVG unwrapped enum raw class changed' unless value.class.name == expected_class
      raise 'SVG unwrapped enum value changed' unless SvgSettingsRead.records[name] == Digest::SHA256.hexdigest(value.to_s)
      types[name] = {value_class: value.class.name, frozen: value.frozen?, enum_class: klass}
    end
    raise 'SVG unwrapped enum not reached' unless types.key?('desktop_category_page_style') && types.key?('mobile_category_page_style')
    record[:svg_enums] = types
    record
  end
end
class ListBodyContext
  include SvgEnumViewProtocol
  def observation; svg_enum_stage_observation; end
end
