# frozen_string_literal: true
require_relative 'svg_onebox_classes'
module SvgOneboxRead
  def self.verify_source!
    root = RequestAssetCapability::ROOT
    SvgOneboxSourceMembers::HASHES.each do |relative, expected|
      path = File.join(root, relative)
      RequestAssetServing.verified_member!(root, path)
      bytes = File.read(path)
      bytes += '\n' if ENV.fetch('FIDELITY_SVG_ONEBOX_FAULT', '') == 'wrong-source'
      raise ArgumentError, 'Onebox source member changed' unless Digest::SHA256.hexdigest(bytes) == expected
    end
    nil
  end
  def self.verify_classes!
    verify_source!
    klass = SvgOneboxReadClasses::ReadOneboxClass
    fault = ENV.fetch('FIDELITY_SVG_ONEBOX_FAULT', '')
    klass = SvgOneboxReadClasses::ReadLocaleClass if fault == 'wrong-class'
    klass = SvgOneboxReadClasses::WrappedMutation if fault == 'wrapped-class'
    raise ArgumentError, 'Onebox getter unexpectedly wrapped' if klass.respond_to?(:wrap)
    raise ArgumentError, 'Onebox getter wrong source class' unless klass == SvgOneboxReadClasses::ReadOneboxClass
    raise ArgumentError, 'Onebox source hierarchy changed' unless klass.superclass == SvgOneboxReadClasses::ReadLocaleClass && SvgOneboxReadClasses::ReadLocaleClass.superclass == SvgOneboxReadClasses::ReadEnumClass
    parent = SvgOneboxReadClasses::ReadLocaleClass.read_lock
    child = SvgOneboxReadClasses::ReadOneboxClass.read_lock
    child = parent if fault == 'aliased-lock'
    raise ArgumentError, 'Onebox source locks not Mutex' unless parent.is_a?(Mutex) && child.is_a?(Mutex)
    raise ArgumentError, 'Onebox source locks aliased' if parent.equal?(child)
    raise ArgumentError, 'Onebox source lock identity changed' unless child.equal?(SvgOneboxReadClasses::ReadOneboxClass.read_lock) && parent.equal?(SvgOneboxReadClasses::ReadLocaleClass.read_lock)
    raise ArgumentError, 'Onebox inherited metadata lookup changed' unless SvgOneboxReadClasses::ReadOneboxClass.translate_names? && !SvgOneboxReadClasses::ReadEnumClass.translate_names?
    nil
  end
  def self.class_facts
    verify_classes!
    {locks_distinct: !SvgOneboxReadClasses::ReadLocaleClass.read_lock.equal?(SvgOneboxReadClasses::ReadOneboxClass.read_lock), inherited_translate_names: SvgOneboxReadClasses::ReadOneboxClass.translate_names?, wraps: SvgOneboxReadClasses::ReadOneboxClass.respond_to?(:wrap)}
  end
  def self.current
    verify_classes!
    definition = SvgSettingsRead.definition('onebox_locale')
    options = definition.options
    raise ArgumentError, 'unsupported Onebox getter declaration' unless definition.data_type == 7 && options['type'] == 'enum' && options['enum'] == 'OneboxLocaleSiteSetting' && definition.default_value.is_a?(String) && !definition.themeable? && !options.key?('portable_source_override') && !options.key?('upcoming_change') && !options.key?('upcoming_change_default_override') && !options.key?('mandatory_values') && !options.key?('locale_default')
    store = SiteSetting.portable_store
    site = SiteSetting.portable_site
    value = store.svg_source_current(site)['onebox_locale']
    if value.nil?
      store.refresh!(site)
      value = store.svg_source_current(site)['onebox_locale']
    end
    raise TypeError, 'Onebox getter current must be String' unless value.is_a?(String) && value.class == String
    value
  end
  def self.read
    value = current
    value = 123 if ENV.fetch('FIDELITY_SVG_ONEBOX_FAULT', '') == 'wrong-type'
    raise TypeError, 'Onebox getter result must be String' unless value.is_a?(String) && value.class == String
    text = value.to_s
    text = text.dup if ENV.fetch('FIDELITY_SVG_ONEBOX_FAULT', '') == 'copied-result'
    text += '-wrong' if ENV.fetch('FIDELITY_SVG_ONEBOX_FAULT', '') == 'wrong-result'
    text
  end
  def self.note(text)
    raw = current
    raise TypeError, 'Onebox consumer String type changed' unless text.class == String
    raise 'Onebox getter result changed' unless text == raw
    raise 'Onebox getter String identity changed' unless text.equal?(raw)
    raise 'Onebox getter String freeze changed' unless text.frozen? == raw.frozen?
    @result = text
    nil
  end
  def self.result; @result; end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'onebox_locale' ? 'onebox_read_enum' : additional_kind_without_onebox(name)
  end
  def self.read(name, warn: true)
    name == 'onebox_locale' ? SvgOneboxRead.read : read_without_onebox(name, warn: warn)
  end
  def self.record(name, text)
    SvgOneboxRead.note(text) if name == 'onebox_locale'
    record_without_onebox(name, text)
  end
end
module SvgOneboxViewProtocol
  def svg_onebox_stage_observation
    record = svg_media_convert_stage_observation
    value = SvgOneboxRead.result
    raise 'Onebox getter result unacquired' unless value.is_a?(String)
    record[:svg_onebox] = {value_digest: Digest::SHA256.hexdigest(value), value_class: value.class.name, frozen: value.frozen?, raw_identity: value.equal?(SvgOneboxRead.current), class_facts: SvgOneboxRead.class_facts}
    record
  end
end
class ListBodyContext
  include SvgOneboxViewProtocol
  def observation; svg_onebox_stage_observation; end
end
