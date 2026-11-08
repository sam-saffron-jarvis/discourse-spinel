# frozen_string_literal: true
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'top_menu' ? 'acquired_top_menu' : nil
  end
  def self.read(name, warn: true)
    if name == 'top_menu'
      value = SiteSetting.top_menu
      if ENV.fetch('FIDELITY_SVG_TOP_MENU_FAULT', '') == 'raw-default'
        wrong = definition(name).default_value.to_s
        raise 'SVG top_menu special getter bypassed' unless wrong == value
        value = wrong
      end
      value.to_s
    else
      read_with_legacy(name, warn: warn)
    end
  end
end
module SvgTopMenuViewProtocol
  def svg_top_menu_stage_observation
    record = svg_legacy_stage_observation
    expected = Digest::SHA256.hexdigest(SiteSetting.top_menu.to_s)
    actual = SvgSettingsRead.records['top_menu']
    raise 'SVG source top_menu getter not acquired' unless actual == expected
    record[:svg_top_menu] = {value_digest: actual, source_named_getter: true, raw_default_substituted: false}
    record
  end
end
class ListBodyContext
  include SvgTopMenuViewProtocol
  def observation; svg_top_menu_stage_observation; end
end
