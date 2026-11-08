# frozen_string_literal: true

class BasicUserSerializer < ApplicationSerializer
  include UserStatusMixin



  def name
    Hash === user ? user[:name] : user.try(:name)
  end

  def include_name?
    SiteSetting.enable_names?
  end

  def avatar_template
    if Hash === object
      User.avatar_template(user[:username], user[:uploaded_avatar_id])
    else
      user&.avatar_template
    end
  end

  def user; raise ArgumentError, "unsupported non-User basic serializer object" unless object.is_a?(User); object; end

  def user_is_current_user
    object.id == scope.user&.id
  end

  def categories_with_notification_level(lookup_level)
    category_user_notification_levels
      .select { |id, level| level == CategoryUser.notification_levels[lookup_level] }
      .keys
  end

  def category_user_notification_levels
    @category_user_notification_levels ||= CategoryUser.notification_levels_for(user)
  end

  public
  def id
    object.id
  end

  def username
    object.username
  end

  def include_id?; true; end

  def include_username?; true; end

  def include_avatar_template?; true; end

  def attributes
    result = {}
    result[:status] = status if include?(:status)
    result[:id] = id if include?(:id)
    result[:username] = username if include?(:username)
    result[:name] = name if include?(:name)
    result[:avatar_template] = avatar_template if include?(:avatar_template)
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
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
