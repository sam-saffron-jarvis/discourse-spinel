# frozen_string_literal: true

class TagSerializer < ApplicationSerializer




  def slug
    object.slug_for_url
  end

  def name
    translated =
      (object.get_localization&.name if ContentLocalization.show_translated_tag?(object, scope))
    translated || object.name
  end

  def description
    translated =
      if ContentLocalization.show_translated_tag?(object, scope)
        object.get_localization&.description
      end
    translated || object.description
  end

  def description_cooked
    translated =
      if ContentLocalization.show_translated_tag?(object, scope)
        object.get_localization&.description_cooked
      end
    translated || object.description_cooked
  end

  def topic_count; Tag.topic_count_for(object, scope); end

  def staff; raise ArgumentError, "unsupported nonempty tag serialization profile"; end

  def include_localizations?
    SiteSetting.content_localization_enabled && object.localizations.loaded?
  end

  public
  def id
    object.id
  end

  def include_id?; true; end

  def include_name?; true; end

  def include_slug?; true; end

  def include_topic_count?; true; end

  def include_staff?; true; end

  def include_description?; true; end

  def include_description_cooked?; true; end

  def attributes
    result = {}
    result[:id] = id if include?(:id)
    result[:name] = name if include?(:name)
    result[:slug] = slug if include?(:slug)
    result[:topic_count] = topic_count if include?(:topic_count)
    result[:staff] = staff if include?(:staff)
    result[:description] = description if include?(:description)
    result[:description_cooked] = description_cooked if include?(:description_cooked)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :id; include_id?
when :name; include_name?
when :slug; include_slug?
when :topic_count; include_topic_count?
when :staff; include_staff?
when :description; include_description?
when :description_cooked; include_description_cooked?
when :localizations; include_localizations?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def localizations
    object.localizations
  end

  def include_associations!
    if include?(:localizations)
      value = localizations
      if [:id, :ids].include?(:objects)
        @node[:localization_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TagLocalizationSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :localizations, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:localizations] = value.map { |item| TagLocalizationSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    nil
  end
end
