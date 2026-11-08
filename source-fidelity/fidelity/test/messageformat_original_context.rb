# frozen_string_literal: true
require 'active_support/core_ext/string/indent'
require_relative 'locale_layout_original_context'
require 'messageformat'
module OriginalOwnedMessageFormatCompiler
  def self.compile(locales, messages, strict: true)
    compiler = ::MessageFormat::Compiler.new(locales, messages, strict: strict)
    begin
      compiler.compile
    ensure
      compiler.context.dispose
    end
  end
end
module OriginalClientLocaleSource
  MessageFormat = OriginalOwnedMessageFormatCompiler
end
module OriginalAssetLifecycle
  module Rails
    def self.logger; OriginalMessageFormatLogSink; end
  end
end
module OriginalMessageFormatLogSink
  def self.error(message)
    lease = CategoryCacheBootstrap.lease
    lease.check!(lease.host, lease.port)
    raise ArgumentError, 'unbounded MessageFormat error log' unless message.is_a?(String) && message.bytesize <= 1_048_576
    $stderr.puts('FIDELITY_OWNED_MESSAGEFORMAT_LOG ' + message)
  end
end
module OriginalExtraLocaleSource
  class << self
    def bundle_js(bundle, locale:)
      if bundle == OVERRIDES_BUNDLE
        RequestClientLocaleBootstrap.events << 'locale_bundle_acquisition:overrides'
        raise HtmlRenderingBoundary, 'actual main/MF locale scripts/preloads acquired; client override bundle acquisition pending'
      end
      raise ArgumentError, 'unsupported original locale bundle' unless bundle == MAIN_BUNDLE || bundle == MF_BUNDLE
      RequestMessageFormatCompiler.validate_source! if bundle == MF_BUNDLE
      value = source_bundle_js(bundle, locale: locale)
      if bundle == MAIN_BUNDLE
        RequestClientLocaleBootstrap.last_main_script = value
        RequestClientLocaleBootstrap.main_builds += 1
      else
        RequestClientLocaleBootstrap.last_mf_script = value
        RequestClientLocaleBootstrap.mf_builds += 1
      end
      value
    end
  end
end
class OriginalListBodyContext
  include MessageFormatViewProtocol
  def observation; messageformat_stage_observation; end
end
