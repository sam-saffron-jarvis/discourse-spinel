# frozen_string_literal: true
require_relative 'svg_legacy_source'
module SvgLegacyRead
  def self.reset; @calls = []; nil; end
  def self.calls; @calls ||= []; end
  def self.note(name, target, warn)
    raise ArgumentError, 'unsupported SVG deprecated warning profile' unless warn == false
    raise ArgumentError, 'SVG deprecated alias selected wrong source getter' unless SvgLegacyDeclarations::ALIASES.key?(name) && target == '_' + name
    calls << "#{name}|#{target}|#{warn}"
    nil
  end
end
module SvgSettingsRead
  def self.legacy_getters_supported?; true; end
  def self.bind
    SvgLegacyRead.reset
    bind_without_legacy_audit
  end
  def self.read(name, warn: true)
    if SvgLegacyDeclarations::ALIASES.key?(name)
      warn = true if ENV.fetch('FIDELITY_SVG_LEGACY_FAULT', '') == 'wrong-warning'
      target = ENV.fetch('FIDELITY_SVG_LEGACY_FAULT', '') == 'replacement-getter' ? SvgLegacyDeclarations::ALIASES[name] : '_' + name
      SvgLegacyRead.note(name, target, warn)
    end
    read_plain_or_upload(name)
  end
end
module SvgLegacyViewProtocol
  def svg_legacy_stage_observation
    record = svg_settings_stage_observation
    calls = SvgLegacyRead.calls
    names = SvgSettingsRead.records.keys.select { |name| SvgLegacyDeclarations::ALIASES.key?(name) }
    raise 'SVG deprecated source forwarding missing' if names.empty?
    expected = names.map { |name| "#{name}|_#{name}|false" }
    raise 'SVG deprecated source forwarding changed' unless calls == expected
    record[:svg_legacy] = {calls: calls, warn_false: true, alias_forwarded_to_replacement: false}
    record
  end
end
class ListBodyContext
  include SvgLegacyViewProtocol
  def observation; svg_legacy_stage_observation; end
end
