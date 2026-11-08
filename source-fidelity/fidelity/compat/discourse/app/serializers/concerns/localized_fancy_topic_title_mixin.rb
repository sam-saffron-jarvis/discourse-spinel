# frozen_string_literal: true

module LocalizedFancyTopicTitleMixin


  def fancy_title
    translated_title || _topic.fancy_title
  end

  def include_fancy_title?
    !_topic.nil? && _topic&.fancy_title.present?
  end

  def fancy_title_localized
    translated_title.present?
  end

  def include_fancy_title_localized?
    SiteSetting.content_localization_enabled && include_fancy_title?
  end

  def locale
    _topic.locale
  end

  def include_locale?
    SiteSetting.content_localization_enabled && _topic.present?
  end

  private

  def _topic; raise ArgumentError, "unsupported non-Topic serializer object" unless object.class == Topic; @_topic ||= object; end

  def translated_title
    ContentLocalization.translated_topic_fancy_title(_topic, scope)
  end

  public

end
