# frozen_string_literal: true
require_relative 'original_svg_enum_source'
module OriginalSvgSettingsReference
  class TypeView
    def get_type(name)
      definition = SvgSettingsRead.definition(name.to_s)
      definition.options.key?('enum') ? :enum : SvgSettingsDeclarations::TYPES.fetch(definition.data_type)
    end
    def get_enum_class(name)
      key = name.to_s
      klass = OriginalSvgEnumSource::CLASSES[key]
      unless klass.nil?
        raise 'SVG original enum unexpectedly wrapped' if klass.respond_to?(:wrap)
        return klass
      end
      definition = SvgSettingsRead.definition(key)
      return nil unless definition.options.key?('enum')
      raise 'unsupported SVG original enum wrapper' unless definition.options['portable_unwrapped_enum'] == true
      nil
    end
  end
end
class OriginalListBodyContext
  include SvgEnumViewProtocol
  def observation; svg_enum_stage_observation; end
end
