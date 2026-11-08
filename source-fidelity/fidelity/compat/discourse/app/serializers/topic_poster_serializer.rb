# frozen_string_literal: true

class TopicPosterSerializer < ApplicationSerializer






  public
  def extras
    object.extras
  end

  def description
    object.description
  end

  def include_extras?; true; end

  def include_description?; true; end

  def include_user?; true; end

  def include_primary_group?; true; end

  def include_flair_group?; true; end

  def attributes
    result = {}
    result[:extras] = extras if include?(:extras)
    result[:description] = description if include?(:description)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :extras; include_extras?
when :description; include_description?
when :user; include_user?
when :primary_group; include_primary_group?
when :flair_group; include_flair_group?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def user
    object.user
  end

  def primary_group
    object.primary_group
  end

  def flair_group
    object.flair_group
  end

  def include_associations!
    if include?(:user)
      value = user
      if [:id, :ids].include?(_embed)
        @node[:user_id] = value.nil? ? nil : value.id
        serializables = value.nil? ? [] : [PosterSerializer.new(value, @options)]
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :users, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(_embed)
        @node[:user] = value.nil? ? nil : PosterSerializer.new(value, @options).serializable_hash
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:primary_group)
      value = primary_group
      if [:id, :ids].include?(_embed)
        @node[:primary_group_id] = value.nil? ? nil : value.id
        serializables = value.nil? ? [] : [PrimaryGroupSerializer.new(value, @options)]
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :primary_groups, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(_embed)
        @node[:primary_group] = value.nil? ? nil : PrimaryGroupSerializer.new(value, @options).serializable_hash
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:flair_group)
      value = flair_group
      if [:id, :ids].include?(_embed)
        @node[:flair_group_id] = value.nil? ? nil : value.id
        serializables = value.nil? ? [] : [FlairGroupSerializer.new(value, @options)]
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :flair_groups, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(_embed)
        @node[:flair_group] = value.nil? ? nil : FlairGroupSerializer.new(value, @options).serializable_hash
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    nil
  end
end
