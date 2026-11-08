# frozen_string_literal: true

# The most basic attributes of a topic that we need to create a link for it.
class BasicTopicSerializer < ApplicationSerializer
  include LocalizedFancyTopicTitleMixin



  public
  def id
    object.id
  end

  def title
    object.title
  end

  def slug
    object.slug
  end

  def posts_count
    object.posts_count
  end

  def include_id?; true; end

  def include_title?; true; end

  def include_slug?; true; end

  def include_posts_count?; true; end

  def attributes
    result = {}
    result[:fancy_title] = fancy_title if include?(:fancy_title)
    result[:fancy_title_localized] = fancy_title_localized if include?(:fancy_title_localized)
    result[:locale] = locale if include?(:locale)
    result[:id] = id if include?(:id)
    result[:title] = title if include?(:title)
    result[:slug] = slug if include?(:slug)
    result[:posts_count] = posts_count if include?(:posts_count)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :fancy_title; include_fancy_title?
when :fancy_title_localized; include_fancy_title_localized?
when :locale; include_locale?
when :id; include_id?
when :title; include_title?
when :slug; include_slug?
when :posts_count; include_posts_count?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
