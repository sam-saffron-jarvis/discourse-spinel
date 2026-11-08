# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      raise ArgumentError, 'unsupported acquired original SVG getter' unless name == 'top_menu'
      view = OriginalHtmlStageSource::LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
      OriginalHtmlStageSource::UpcomingChanges.live_provider = view
      enabled = OriginalHtmlStageSource::UpcomingChanges.enabled?(:enable_unified_new)
      view.defaults.activate_upcoming_change_override(:enable_unified_new) if enabled
      value = view.defaults.all[:top_menu]
      value = view.current[:top_menu] if view.setting_modified_from_default?(:top_menu)
      value
    end
  end
end
class OriginalListBodyContext
  include SvgTopMenuViewProtocol
  def observation; svg_top_menu_stage_observation; end
end
