# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      return acquired_getter_value_without_experimental(name) unless SvgExperimentalDeclarations::NAMES.include?(name)
      view = OriginalHtmlStageSource::LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
      OriginalHtmlStageSource::UpcomingChanges.live_provider = view
      OriginalHtmlStageSource::UpcomingChanges.enabled?(name.to_sym)
    end
  end
end
class OriginalListBodyContext
  include SvgExperimentalViewProtocol
  def observation; svg_experimental_stage_observation; end
end
