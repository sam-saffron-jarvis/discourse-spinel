# frozen_string_literal: true
# Full return from settings_hash is observed before the still-unacquired SVG scan.
module SvgSnapshotRead
  def self.capture(value)
    raise TypeError, 'SVG full settings snapshot must be Hash' unless value.is_a?(Hash)
    names = SvgSettingsRead.names.reject { |name| SvgSettingsRead.themeable?(name) }
    raise 'SVG settings getter order changed' unless value.keys == names.map(&:to_sym) && SvgSettingsRead.records.keys == names
    value.each do |key, text|
      raise TypeError, 'SVG full snapshot value must remain String' unless text.is_a?(String) && text.class == String
      expected = SvgSettingsRead.definition(key.to_s).secret? ? '[secret-not-recorded]' : Digest::SHA256.hexdigest(text)
      raise 'SVG full snapshot value changed' unless SvgSettingsRead.records[key.to_s] == expected
    end
    @count = value.size
    nil
  end
  def self.count; @count; end
end
module RequestSvgBootstrap
  def self.settings_hash
    events = @events
    raise 'SVG events not bound' unless events.is_a?(Array)
    events << 'svg_settings_hash_acquisition'
    value = SvgSettingsRead.settings_hash
    SvgSnapshotRead.capture(value)
    raise HtmlRenderingBoundary, 'actual SVG full settings_hash returned; icon extraction acquisition pending'
  end
end
module SvgSettingsViewProtocol
  def svg_settings_stage_observation
    record = svg_cache_stage_observation
    raise 'SVG full snapshot return not acquired' unless SvgSnapshotRead.count == SvgSettingsRead.records.size
    raise 'SVG full snapshot incorrectly reported pending getter' unless SvgSettingsRead.pending_name.nil?
    record[:svg_settings] = {names: SvgSettingsRead.records.keys, value_digests: SvgSettingsRead.records, pending_getter: nil, key_projection_only: false, full_snapshot_returned: true}
    record
  end
end
