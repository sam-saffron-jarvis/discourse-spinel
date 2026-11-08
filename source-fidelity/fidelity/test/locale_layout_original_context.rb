# frozen_string_literal: true
require 'active_support/core_ext/object/json'
ActiveSupport::JSON.singleton_class.define_method(:encode, OriginalClientJSONEncode)
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/string/inflections'
require_relative 'request_asset_original_context'
require_relative 'original_client_locale_source'
require_relative 'original_client_locale_bindings'
require_relative 'original_extra_locale_source'
require_relative 'original_locale_layout_helpers'
require_relative 'original_client_date_backend'
require_relative 'original_client_fallbacks'
module OriginalClientLocaleI18n
  Backend = ::I18n::Backend
  def self.locale; ::I18n.locale; end
  def self.with_locale(locale, &block); ::I18n.with_locale(locale, &block); end
  def self.fallbacks; @fallbacks ||= ::I18n::Backend::FallbackLocaleList.new; end
  def self.t(key)
    @backend ||= OriginalClientDateBackend.new
    locale = ::I18n.locale
    @loaded ||= {}
    unless @loaded[locale]
      @backend.load_translations(RequestClientLocaleBootstrap.root + '/config/locales/server.' + locale.to_s + '.yml')
      @loaded[locale] = true
    end
    @backend.send(:lookup, locale, key, [], {overrides: {locale => RequestClientLocaleBootstrap.overrides(locale)}})
  end
end
module OriginalClientLocaleSource
  I18n = OriginalClientLocaleI18n
  Rails = OriginalAssetLifecycle::Rails
  module VendoredAssets
    DIRECTORY = 'vendor/runtime_node_modules'
    def self.path(relative_path); OriginalAssetLifecycle::Rails.root.join(DIRECTORY, relative_path); end
  end
end
module OriginalExtraLocaleSource
  RailsMultisite = OriginalCategoryCacheApplication::RailsMultisite
  JsLocaleHelper = OriginalClientLocaleSource
  module GlobalSetting
    def self.cdn_url; ListHeadImages.configuration.value('cdn_url'); end
  end
  class << self
    alias_method :unobserved_url, :url
    alias_method :source_bundle_js, :bundle_js
    def url(bundle, **options)
      RequestClientLocaleBootstrap.events << "locale_bundle_acquisition:#{bundle}"
      unobserved_url(bundle, **options)
    end
    def bundle_js(bundle, locale:)
      if bundle == MF_BUNDLE
        raise HtmlRenderingBoundary, 'actual main locale JS/digest/preload acquired; MessageFormat compiler acquisition pending'
      end
      raise ArgumentError, 'unsupported original locale bundle before MessageFormat' unless bundle == MAIN_BUNDLE
      value = source_bundle_js(bundle, locale: locale)
      RequestClientLocaleBootstrap.last_main_script = value
      RequestClientLocaleBootstrap.main_builds += 1
      value
    end
  end
end
class ExtraLocalesController
  def self.url(bundle, **options); OriginalExtraLocaleSource.url(bundle, **options); end
end
class OriginalListBodyContext
  include OriginalLocaleLayoutHelpers
  include RequestLocaleLayoutProtocol
  def layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @output_buffer = ActionView::OutputBuffer.new
    begin
      render_application_layout
      raise 'original locale layout unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def observation; locale_stage_observation; end
end
