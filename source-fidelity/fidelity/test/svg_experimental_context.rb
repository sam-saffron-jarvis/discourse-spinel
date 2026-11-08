# frozen_string_literal: true
require_relative 'svg_experimental_source'
module SvgExperimentalRead
  def self.enabled(name)
    SiteSetting.portable_store.svg_change_enabled(name, SiteSetting.portable_site, HtmlUpcomingStatuses::VALUES)
  end
  def self.read(name)
    value = enabled(name)
    target = ENV.fetch('FIDELITY_SVG_EXPERIMENTAL_TARGET', '')
    fault = target == '' || target == name ? ENV.fetch('FIDELITY_SVG_EXPERIMENTAL_FAULT', '') : ''
    value = 'not-Boolean' if fault == 'wrong-type'
    if fault == 'permanent-as-default' && SvgSettingsRead.definition(name).options['upcoming_change']['status'] == 'permanent'
      value = SvgSettingsRead.definition(name).default_value
    end
    raise TypeError, 'SVG experimental getter result not Boolean' unless value == true || value == false
    text = value.to_s
    text += '-wrong' if fault == 'wrong-result'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    SvgExperimentalDeclarations::NAMES.include?(name) ? 'acquired_experimental_core_flag' : additional_kind_without_experimental(name)
  end
  def self.read(name, warn: true)
    SvgExperimentalDeclarations::NAMES.include?(name) ? SvgExperimentalRead.read(name) : read_without_experimental(name, warn: warn)
  end
end
module SvgExperimentalViewProtocol
  def svg_experimental_stage_observation
    record = svg_onebox_stage_observation
    values = {}
    SvgExperimentalDeclarations::NAMES.each do |name|
      next unless SvgSettingsRead.records.key?(name)
      value = SvgExperimentalRead.enabled(name)
      digest = Digest::SHA256.hexdigest(value.to_s)
      raise 'SVG experimental source result changed' unless digest == SvgSettingsRead.records[name]
      values[name] = {value_class: value.class.name, value_digest: digest, status: SvgSettingsRead.definition(name).options['upcoming_change']['status']}
    end
    raise 'SVG experimental first getter not acquired' unless values.key?('enable_user_menu_mentions_tab')
    record[:svg_experimental] = values
    record
  end
end
class ListBodyContext
  include SvgExperimentalViewProtocol
  def observation; svg_experimental_stage_observation; end
end
