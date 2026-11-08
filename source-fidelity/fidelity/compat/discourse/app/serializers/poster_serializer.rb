# frozen_string_literal: true

class PosterSerializer < BasicUserSerializer
  include UserPrimaryGroupMixin

  public
  def id
    object.id
  end

  def username
    object.username
  end

  def trust_level
    object.trust_level
  end

  def include_id?; true; end

  def include_username?; true; end

  def include_avatar_template?; true; end

  def include_trust_level?; true; end

  def attributes
    result = {}
    result[:status] = status if include?(:status)
    result[:id] = id if include?(:id)
    result[:username] = username if include?(:username)
    result[:name] = name if include?(:name)
    result[:avatar_template] = avatar_template if include?(:avatar_template)
    result[:flair_name] = flair_name if include?(:flair_name)
    result[:flair_url] = flair_url if include?(:flair_url)
    result[:flair_bg_color] = flair_bg_color if include?(:flair_bg_color)
    result[:flair_color] = flair_color if include?(:flair_color)
    result[:flair_group_id] = flair_group_id if include?(:flair_group_id)
    result[:primary_group_name] = primary_group_name if include?(:primary_group_name)
    result[:admin] = admin if include?(:admin)
    result[:moderator] = moderator if include?(:moderator)
    result[:trust_level] = trust_level if include?(:trust_level)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :status; include_status?
when :id; include_id?
when :username; include_username?
when :name; include_name?
when :avatar_template; include_avatar_template?
when :flair_name; include_flair_name?
when :flair_url; include_flair_url?
when :flair_bg_color; include_flair_bg_color?
when :flair_color; include_flair_color?
when :flair_group_id; include_flair_group_id?
when :primary_group_name; include_primary_group_name?
when :admin; include_admin?
when :moderator; include_moderator?
when :trust_level; include_trust_level?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
