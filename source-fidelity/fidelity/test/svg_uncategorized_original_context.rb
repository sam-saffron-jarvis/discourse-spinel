# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      return acquired_getter_value_without_uncategorized(name) unless name == 'remove_and_replace_uncategorized'
      view = OriginalHtmlStageSource::LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
      OriginalHtmlStageSource::UpcomingChanges.live_provider = view
      OriginalHtmlStageSource::UpcomingChanges.enabled?(:remove_and_replace_uncategorized)
    end
  end
end
class OriginalListBodyContext
  include SvgUncategorizedViewProtocol
  def observation; svg_uncategorized_stage_observation; end
end
