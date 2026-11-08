# frozen_string_literal: true

class CategoryBadgeSerializer < ApplicationSerializer


  def include_parent_category_id?
    parent_category_id.present?
  end

  def name
    return I18n.t("uncategorized_category_name") if object.uncategorized?

    translated =
      if ContentLocalization.show_translated_category?(object, scope)
        object.get_localization&.name
      else
        object.name
      end

    translated || object.name
  end

  def description_text
    if object.uncategorized?
      I18n.t("category.uncategorized_description", locale: SiteSetting.default_locale)
    else
      object.description_text
    end
  end

  public
  def id
    object.id
  end

  def slug
    object.slug
  end

  def color
    object.color
  end

  def text_color
    object.text_color
  end

  def style_type
    object.style_type
  end

  def icon
    object.icon
  end

  def emoji
    object.emoji
  end

  def read_restricted
    object.read_restricted
  end

  def parent_category_id
    object.parent_category_id
  end

  def include_id?; true; end

  def include_name?; true; end

  def include_slug?; true; end

  def include_color?; true; end

  def include_text_color?; true; end

  def include_style_type?; true; end

  def include_icon?; true; end

  def include_emoji?; true; end

  def include_read_restricted?; true; end

  def attributes
    result = {}
    result[:id] = id if include?(:id)
    result[:name] = name if include?(:name)
    result[:slug] = slug if include?(:slug)
    result[:color] = color if include?(:color)
    result[:text_color] = text_color if include?(:text_color)
    result[:style_type] = style_type if include?(:style_type)
    result[:icon] = icon if include?(:icon)
    result[:emoji] = emoji if include?(:emoji)
    result[:read_restricted] = read_restricted if include?(:read_restricted)
    result[:parent_category_id] = parent_category_id if include?(:parent_category_id)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :id; include_id?
when :name; include_name?
when :slug; include_slug?
when :color; include_color?
when :text_color; include_text_color?
when :style_type; include_style_type?
when :icon; include_icon?
when :emoji; include_emoji?
when :read_restricted; include_read_restricted?
when :parent_category_id; include_parent_category_id?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
