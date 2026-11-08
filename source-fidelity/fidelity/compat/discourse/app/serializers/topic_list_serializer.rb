# frozen_string_literal: true

class TopicListSerializer < ApplicationSerializer







  def initialize(object, options = {})
    super
    options[:filter] = object.filter
  end

  def can_create_topic
    scope.can_create?(Topic)
  end

  def include_shared_drafts?
    object.shared_drafts.present?
  end

  def include_filter_new_topic_ids?
    !object.filter_new_topic_ids.nil?
  end

  def include_filter_option_info?
    object.filter_option_info.present?
  end

  def include_for_period?
    for_period.present?
  end

  def include_more_topics_url?
    object.more_topics_url.present? && (object.topics.size == object.per_page)
  end

  def include_top_tags?
    Tag.include_tags?
  end

  def include_tags?
    SiteSetting.tagging_enabled && object.tags.present?
  end

  def include_categories?
    scope.can_lazy_load_categories?
  end

  public
  def filter
    object.filter
  end

  def more_topics_url
    object.more_topics_url
  end

  def for_period
    object.for_period
  end

  def per_page
    object.per_page
  end

  def top_tags
    object.top_tags
  end

  def tags
    object.tags
  end

  def shared_drafts
    object.shared_drafts
  end

  def filter_option_info
    object.filter_option_info
  end

  def filter_new_topic_ids
    object.filter_new_topic_ids
  end

  def include_can_create_topic?; true; end

  def include_filter?; true; end

  def include_per_page?; true; end

  def include_topics?; true; end

  def attributes
    result = {}
    result[:can_create_topic] = can_create_topic if include?(:can_create_topic)
    result[:filter] = filter if include?(:filter)
    result[:more_topics_url] = more_topics_url if include?(:more_topics_url)
    result[:for_period] = for_period if include?(:for_period)
    result[:per_page] = per_page if include?(:per_page)
    result[:top_tags] = top_tags if include?(:top_tags)
    result[:tags] = tags if include?(:tags)
    result[:shared_drafts] = shared_drafts if include?(:shared_drafts)
    result[:filter_option_info] = filter_option_info if include?(:filter_option_info)
    result[:filter_new_topic_ids] = filter_new_topic_ids if include?(:filter_new_topic_ids)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :can_create_topic; include_can_create_topic?
when :filter; include_filter?
when :more_topics_url; include_more_topics_url?
when :for_period; include_for_period?
when :per_page; include_per_page?
when :top_tags; include_top_tags?
when :tags; include_tags?
when :shared_drafts; include_shared_drafts?
when :filter_option_info; include_filter_option_info?
when :filter_new_topic_ids; include_filter_new_topic_ids?
when :topics; include_topics?
when :categories; include_categories?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def topics
    object.topics
  end

  def shared_drafts
    object.shared_drafts
  end

  def tags
    object.tags
  end

  def categories
    object.categories
  end

  def include_associations!
    if include?(:topics)
      value = topics
      if [:id, :ids].include?(:objects)
        @node[:topic_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TopicListItemSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :topics, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:topics] = value.map { |item| TopicListItemSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:shared_drafts)
      value = shared_drafts
      if [:id, :ids].include?(:objects)
        @node[:shared_draft_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TopicListItemSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :shared_drafts, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:shared_drafts] = value.map { |item| TopicListItemSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:tags)
      value = tags
      if [:id, :ids].include?(:objects)
        @node[:tag_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TagSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :tags, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:tags] = value.map { |item| TagSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:categories)
      value = categories
      if [:id, :ids].include?(:objects)
        @node[:categorie_ids] = value.map { |item| item.id }
        serializables = value.map { |item| CategoryBadgeSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :categories, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:categories] = value.map { |item| CategoryBadgeSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    nil
  end
end
