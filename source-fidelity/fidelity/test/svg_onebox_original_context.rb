# frozen_string_literal: true
require_relative 'original_svg_onebox_classes'
module OriginalSvgOneboxClasses
  class LocaleSiteSetting
    def self.read_lock; @lock; end
    # Guards on entry only. No empty tables/successful validation substituted.
    def self.values; raise ArgumentError, 'original locale UI values unacquired'; end
    def self.language_names; raise ArgumentError, 'original locale language loading unacquired'; end
    def self.supported_locales; raise ArgumentError, 'original locale scanning unacquired'; end
  end
end
module SvgOneboxRead
  def self.class_facts
    verify_source!
    klass = OriginalSvgOneboxClasses::OneboxLocaleSiteSetting
    parent = OriginalSvgOneboxClasses::LocaleSiteSetting
    raise 'original Onebox source hierarchy changed' unless klass.superclass == parent && parent.superclass == OriginalSvgOneboxClasses::EnumSiteSetting
    raise 'original Onebox getter unexpectedly wrapped' if klass.respond_to?(:wrap)
    raise 'original Onebox source locks aliased' unless klass.read_lock.is_a?(Mutex) && parent.read_lock.is_a?(Mutex) && !klass.read_lock.equal?(parent.read_lock)
    raise 'original Onebox source lock changed' unless klass.read_lock.equal?(klass.instance_variable_get(:@lock)) && parent.read_lock.equal?(parent.instance_variable_get(:@lock))
    raise 'original Onebox lexical method owner changed' unless klass.method(:translate_names?).owner == parent.singleton_class
    {locks_distinct: !parent.read_lock.equal?(klass.read_lock), inherited_translate_names: klass.translate_names?, wraps: klass.respond_to?(:wrap)}
  end
end
module OriginalSvgSettingsReference
  class TypeView
    def get_enum_class(name)
      return get_enum_class_without_onebox(name) unless name.to_s == 'onebox_locale'
      SvgOneboxRead.class_facts
      OriginalSvgOneboxClasses::OneboxLocaleSiteSetting
    end
  end
end
class OriginalListBodyContext
  include SvgOneboxViewProtocol
  def observation; svg_onebox_stage_observation; end
end
