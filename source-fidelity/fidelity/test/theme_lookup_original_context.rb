# frozen_string_literal: true
require 'active_support/core_ext/array/access'
require 'active_support/core_ext/string/access'
require_relative 'original_theme_lookup_source'
module OriginalThemeLookupSource
  # Actual enum target declaration already acquired in the source Array path.
  module Theme
    def self.targets; ListThemeArraySource::TARGETS; end
  end
end
class ThemeField
  def ensure_baked!
    ThemeFieldReadBootstrap.note_callback
    needs_baking = !value_baked || compiler_version != ListThemeCompilerSource.compiler_version
    raise ArgumentError, 'unowned Theme field rebake PG effects refused before dispatch' if needs_baking || ENV.fetch('FIDELITY_THEME_FIELD_FAULT', '') == 'rebake-required'
    OriginalThemeFieldCallback.instance_method(:ensure_baked!).bind(self).call
  end
end
class OriginalListBodyContext
  include OriginalThemeLookupHelpers
  include ThemeFieldViewProtocol
  def theme_translations_lookup
    @events << 'theme_translations_acquisition'
    value = original_theme_translations_lookup
    @actual_theme_translations = value.to_s
    @events << 'theme_translations_returned'
    value
  end
  def observation; theme_field_stage_observation; end
end
