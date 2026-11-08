# frozen_string_literal: true
module OriginalHtmlStageSource
  class LiveProviderView
    def enable_local_logins
      SvgLocalLoginRead.note('enable_local_logins', @store.get('enable_local_logins', @site))
    end
    def enable_local_logins_via_email
      SvgLocalLoginRead.note('enable_local_logins_via_email', @store.get('enable_local_logins_via_email', @site))
    end
    def dependency_values
      @definitions.each_with_object({}) do |(name, definition), values|
        raw = definition.options['depends_on_values']
        values[name.to_sym] = raw.transform_keys(&:to_sym) if raw.is_a?(Hash)
      end
    end
  end
end
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      return acquired_getter_value_without_local_login(name) unless name == 'enable_local_logins_via_code'
      SvgLocalLoginRead.reset
      view = OriginalHtmlStageSource::LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
      OriginalHtmlStageSource::UpcomingChanges.live_provider = view
      OriginalHtmlStageSource::UpcomingChanges.enabled?(:enable_local_logins_via_code)
    end
  end
end
class OriginalListBodyContext
  include SvgLocalLoginViewProtocol
  def observation; svg_local_login_stage_observation; end
end
