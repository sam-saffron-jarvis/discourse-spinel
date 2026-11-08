# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      change = SvgDefaultDeclarations::CHANGES[name]
      return acquired_getter_value_without_defaults(name) if change.nil?
      view = OriginalHtmlStageSource::LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
      OriginalHtmlStageSource::UpcomingChanges.live_provider = view
      enabled = OriginalHtmlStageSource::UpcomingChanges.enabled?(change.to_sym)
      view.defaults.activate_upcoming_change_override(change.to_sym) if enabled
      value = view.defaults.all[name.to_sym]
      value = view.current[name.to_sym] if view.setting_modified_from_default?(name)
      value
    end
  end
end
class OriginalListBodyContext
  include SvgDefaultViewProtocol
  def observation; svg_default_stage_observation; end
end
