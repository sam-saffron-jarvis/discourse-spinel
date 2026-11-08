# frozen_string_literal: true
module SvgChoiceListRead
  def self.current
    name = 'content_localization_supported_locales'
    definition = SvgSettingsRead.definition(name)
    options = definition.options
    raise ArgumentError, 'unsupported SVG explicit choice-list profile' unless definition.data_type == 8 && options['type'] == 'list' && options['enum'] == 'LocaleSiteSetting' && !definition.themeable? && !options.key?('portable_source_override') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('mandatory_values')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)[name]
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)[name]
    end
    value
  end
  def self.read
    value = current
    value = [value] if ENV.fetch('FIDELITY_SVG_CHOICE_LIST_FAULT', '') == 'array-result'
    raise TypeError, 'SVG explicit list getter must remain String' unless value.is_a?(String) && value.class == String
    text = value.to_s
    text += '-wrong' if ENV.fetch('FIDELITY_SVG_CHOICE_LIST_FAULT', '') == 'wrong-value'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'content_localization_supported_locales' ? 'explicit_list_choice' : additional_kind_without_choice_list(name)
  end
  def self.read(name, warn: true)
    name == 'content_localization_supported_locales' ? SvgChoiceListRead.read : read_without_choice_list(name, warn: warn)
  end
end
module SvgChoiceListViewProtocol
  def svg_choice_list_stage_observation
    record = svg_wrapped_stage_observation
    value = SvgChoiceListRead.current
    raise TypeError, 'SVG explicit list getter must remain String' unless value.is_a?(String)
    raise 'SVG explicit list getter value changed' unless SvgSettingsRead.records['content_localization_supported_locales'] == Digest::SHA256.hexdigest(value)
    record[:svg_choice_list] = {value_class: value.class.name, frozen: value.frozen?, choice_class_used_for_getter_wrap: false}
    record
  end
end
class ListBodyContext
  include SvgChoiceListViewProtocol
  def observation; svg_choice_list_stage_observation; end
end
