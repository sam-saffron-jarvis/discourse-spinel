# frozen_string_literal: true
class ThemeModifierHelper
  def initialize(request: nil, theme_ids: nil)
    @theme_ids = theme_ids || Theme.transform_ids(request&.env&.[](:resolved_theme_id))
  end

  def serialize_topic_excerpts
    Theme.lookup_modifier(@theme_ids, :serialize_topic_excerpts)
  end

  def csp_extensions
    Theme.lookup_modifier(@theme_ids, :csp_extensions)
  end

  def svg_icons
    Theme.lookup_modifier(@theme_ids, :svg_icons)
  end

  def topic_thumbnail_sizes
    Theme.lookup_modifier(@theme_ids, :topic_thumbnail_sizes)
  end

  def custom_homepage
    Theme.lookup_modifier(@theme_ids, :custom_homepage)
  end

  def serialize_post_user_badges
    Theme.lookup_modifier(@theme_ids, :serialize_post_user_badges)
  end

  def serialize_topic_op_likes_data
    Theme.lookup_modifier(@theme_ids, :serialize_topic_op_likes_data)
  end

  def serialize_topic_is_hot
    Theme.lookup_modifier(@theme_ids, :serialize_topic_is_hot)
  end

  def only_theme_color_schemes
    Theme.lookup_modifier(@theme_ids, :only_theme_color_schemes)
  end
end
