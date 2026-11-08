# frozen_string_literal: true

class FlairGroupSerializer < ApplicationSerializer


  public
  def id
    object.id
  end

  def name
    object.name
  end

  def flair_url
    object.flair_url
  end

  def flair_bg_color
    object.flair_bg_color
  end

  def flair_color
    object.flair_color
  end

  def include_id?; true; end

  def include_name?; true; end

  def include_flair_url?; true; end

  def include_flair_bg_color?; true; end

  def include_flair_color?; true; end

  def attributes
    result = {}
    result[:id] = id if include?(:id)
    result[:name] = name if include?(:name)
    result[:flair_url] = flair_url if include?(:flair_url)
    result[:flair_bg_color] = flair_bg_color if include?(:flair_bg_color)
    result[:flair_color] = flair_color if include?(:flair_color)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :id; include_id?
when :name; include_name?
when :flair_url; include_flair_url?
when :flair_bg_color; include_flair_bg_color?
when :flair_color; include_flair_color?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
