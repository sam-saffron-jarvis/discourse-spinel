# frozen_string_literal: true
require 'active_support/core_ext/hash/slice'
module OriginalExtraLocaleSource
  class << self
    def bundle_js(bundle, locale:)
      raise ArgumentError, 'unsupported original locale bundle' unless [MAIN_BUNDLE, MF_BUNDLE, OVERRIDES_BUNDLE].include?(bundle)
      RequestMessageFormatCompiler.validate_source! if bundle == MF_BUNDLE
      RequestClientLocaleBootstrap.events << 'locale_bundle_acquisition:overrides' if bundle == OVERRIDES_BUNDLE
      value = source_bundle_js(bundle, locale: locale)
      case bundle
      when MAIN_BUNDLE
        RequestClientLocaleBootstrap.last_main_script = value
        RequestClientLocaleBootstrap.main_builds += 1
      when MF_BUNDLE
        RequestClientLocaleBootstrap.last_mf_script = value
        RequestClientLocaleBootstrap.mf_builds += 1
      when OVERRIDES_BUNDLE
        RequestClientLocaleBootstrap.record_overrides(value)
      end
      value
    end
  end
end
class ExtraLocalesController
  def self.observed_override_cache
    site = OriginalCategoryCacheApplication::RailsMultisite::ConnectionManagement.current_db
    OriginalExtraLocaleSource.js_digests.fetch(:site_specific).fetch(site)
  end
  def self.client_overrides_exist?(locale: I18n.locale)
    RequestClientLocaleBootstrap.count_override_check!(locale)
    OriginalExtraLocaleSource.client_overrides_exist?(locale: locale)
  end
end
class OriginalListBodyContext
  include ClientOverrideViewProtocol
  def observation; client_override_stage_observation; end
end
