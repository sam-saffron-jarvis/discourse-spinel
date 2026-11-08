# frozen_string_literal: true
module OriginalSvgSettingsReference
  class TypeView
    def get_type(name)
      definition = SvgSettingsRead.definition(name.to_s)
      return SvgSettingsDeclarations::TYPES.fetch(definition.data_type) if definition.options.key?('type')
      definition.options.key?('enum') ? :enum : SvgSettingsDeclarations::TYPES.fetch(definition.data_type)
    end
    def get_enum_class(name)
      raise 'SVG explicit list incorrectly requested enum wrapper' if name.to_s == 'content_localization_supported_locales'
      get_enum_class_without_choice_list(name)
    end
  end
end
class OriginalListBodyContext
  include SvgChoiceListViewProtocol
  def observation; svg_choice_list_stage_observation; end
end
