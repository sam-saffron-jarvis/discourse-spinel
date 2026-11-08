# frozen_string_literal: true
module SvgUploadedListRead
  def self.assert_empty_input
    name = 'selectable_avatars'
    definition = SvgSettingsRead.definition(name)
    options = definition.options
    raise ArgumentError, 'unsupported SVG uploaded-image-list declaration' unless definition.data_type == 17 && options['type'] == 'uploaded_image_list' && !definition.themeable? && !options.key?('enum') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('portable_source_override')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)[name]
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)[name]
    end
    raise TypeError, 'SVG uploaded-image-list source input not String' unless value.is_a?(String)
    raise ArgumentError, 'nonempty SVG uploaded-image-list row acquisition unsupported' unless value.empty?
    nil
  end
  def self.note_array(value)
    raise TypeError, 'SVG uploaded-image-list getter must return Array' unless value.is_a?(Array) && value.empty?
    raise 'SVG uploaded-image-list source Array frozen' if value.frozen?
    raise 'SVG uploaded-image-list empty branch incorrectly memoized' if !@last_array.nil? && @last_array.equal?(value)
    @last_array = value
    @calls = (@calls || 0) + 1
    nil
  end
  def self.calls; @calls || 0; end
  def self.read
    assert_empty_input
    # Exact actual source return [] branch, never a supplied/seeded array.
    value = []
    value = @prior_array if ENV.fetch('FIDELITY_SVG_UPLOADED_LIST_FAULT', '') == 'memoized-empty' && !@prior_array.nil?
    value = '' if ENV.fetch('FIDELITY_SVG_UPLOADED_LIST_FAULT', '') == 'string-result'
    note_array(value)
    @prior_array = value
    value.to_s
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'selectable_avatars' ? 'acquired_uploaded_image_list' : additional_kind_without_uploaded_list(name)
  end
  def self.read(name, warn: true)
    name == 'selectable_avatars' ? SvgUploadedListRead.read : read_without_uploaded_list(name, warn: warn)
  end
end
module SvgUploadedListViewProtocol
  def svg_uploaded_list_stage_observation
    record = svg_nested_stage_observation
    SvgUploadedListRead.assert_empty_input
    raise 'SVG uploaded-image-list String consumer changed' unless SvgSettingsRead.records['selectable_avatars'] == Digest::SHA256.hexdigest([].to_s)
    calls = SvgUploadedListRead.calls
    raise 'SVG uploaded-image-list getter not acquired' unless calls > 0
    record[:svg_uploaded_list] = {source_input_empty: true, source_array_calls: calls, actual_empty_array: true, fresh_array_each_call: true, empty_branch_memoized: false}
    record
  end
end
class ListBodyContext
  include SvgUploadedListViewProtocol
  def observation; svg_uploaded_list_stage_observation; end
end
