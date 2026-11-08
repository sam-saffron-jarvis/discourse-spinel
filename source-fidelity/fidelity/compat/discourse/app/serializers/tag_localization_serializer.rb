# frozen_string_literal: true

class TagLocalizationSerializer < ApplicationSerializer


  public
  def id
    object.id
  end

  def tag_id
    object.tag_id
  end

  def locale
    object.locale
  end

  def name
    object.name
  end

  def description
    object.description
  end

  def description_cooked
    object.description_cooked
  end

  def include_id?; true; end

  def include_tag_id?; true; end

  def include_locale?; true; end

  def include_name?; true; end

  def include_description?; true; end

  def include_description_cooked?; true; end

  def attributes
    result = {}
    result[:id] = id if include?(:id)
    result[:tag_id] = tag_id if include?(:tag_id)
    result[:locale] = locale if include?(:locale)
    result[:name] = name if include?(:name)
    result[:description] = description if include?(:description)
    result[:description_cooked] = description_cooked if include?(:description_cooked)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :id; include_id?
when :tag_id; include_tag_id?
when :locale; include_locale?
when :name; include_name?
when :description; include_description?
when :description_cooked; include_description_cooked?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
