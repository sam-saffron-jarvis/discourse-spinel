# frozen_string_literal: true
# APPLICATION consumer projection only. No native wrapped getter is represented.
module SvgWrappedRead
  def self.raw
    definition = SvgSettingsRead.definition('duplicate_topic_titles')
    options = definition.options
    raise ArgumentError, 'unsupported SVG wrapped consumer declaration' unless definition.data_type == 7 && options['enum'] == 'DuplicateTopicTitlesSiteSetting' && !definition.themeable? && !options.key?('portable_source_override') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('mandatory_values')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)['duplicate_topic_titles']
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)['duplicate_topic_titles']
    end
    raise TypeError, 'unsupported raw wrapped enum input' unless value.is_a?(String) && value.class == String
    value
  end
  def self.consumer_string
    original = raw
    value = original.dup
    fault = ENV.fetch('FIDELITY_SVG_WRAPPED_FAULT', '')
    value = original if fault == 'alias-current'
    value.freeze if fault == 'frozen-result'
    value += '-wrong' if fault == 'wrong-value'
    value
  end
  def self.note(text)
    original = raw
    raise TypeError, 'SVG wrapped consumer output must be plain String' unless text.is_a?(String) && text.class == String
    raise 'SVG wrapped consumer String aliases raw current' if text.equal?(original)
    raise 'SVG wrapped consumer String frozen' if text.frozen?
    raise 'SVG wrapped consumer String value changed' unless text == original
    @text = text
    nil
  end
  def self.text; @text; end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'duplicate_topic_titles' ? 'wrapped_enum_consumer' : additional_kind_without_wrapped(name)
  end
  def self.read(name, warn: true)
    name == 'duplicate_topic_titles' ? SvgWrappedRead.consumer_string : read_without_wrapped(name, warn: warn)
  end
  def self.record(name, text)
    SvgWrappedRead.note(text) if name == 'duplicate_topic_titles'
    record_without_wrapped_observation(name, text)
  end
end
module SvgWrappedViewProtocol
  def svg_wrapped_stage_observation
    record = svg_uncategorized_stage_observation
    value = SvgWrappedRead.text
    raise 'SVG wrapped consumer not acquired' unless value.is_a?(String)
    record[:svg_wrapped_consumer] = {value_class: value.class.name, frozen: value.frozen?, fresh_from_raw_current: !value.equal?(SvgWrappedRead.raw), value_digest: Digest::SHA256.hexdigest(value)}
    record
  end
end
class ListBodyContext
  include SvgWrappedViewProtocol
  def observation; svg_wrapped_stage_observation; end
end
