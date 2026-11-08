# frozen_string_literal: true

module UserPrimaryGroupMixin


  def primary_group_name
    object&.primary_group&.name
  end

  def include_primary_group_name?
    object&.primary_group.present?
  end

  def include_admin?
    object&.admin
  end

  def admin
    true
  end

  def include_moderator?
    object&.moderator
  end

  def moderator
    true
  end

  public
  include UserFlairMixin
end
