# frozen_string_literal: true
require_relative 'original_svg_legacy_source'
module OriginalSvgSettingsReference
  class View
    include OriginalSvgLegacyMethods
    def install_svg_getter_alias(name)
      key = name.to_s
      replacement = SvgLegacyDeclarations::ALIASES[key]
      setup_deprecated_method(key, replacement, false, SvgLegacyDeclarations::VERSIONS.fetch(key)) unless replacement.nil?
      nil
    end
  end
end
class OriginalListBodyContext
  include SvgLegacyViewProtocol
  def observation; svg_legacy_stage_observation; end
end
