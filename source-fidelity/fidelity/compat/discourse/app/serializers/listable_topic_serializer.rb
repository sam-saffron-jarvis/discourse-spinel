# frozen_string_literal: true

class ListableTopicSerializer < BasicTopicSerializer




  def image_url
    object.image_url(enqueue_if_missing: true)
  end

  def thumbnails
    extra_sizes = theme_modifier_helper.topic_thumbnail_sizes
    object.thumbnail_info(enqueue_if_missing: true, extra_sizes: extra_sizes)
  end

  def include_thumbnails?
    theme_modifier_helper.topic_thumbnail_sizes.present? ||
      DiscoursePluginRegistry.topic_thumbnail_sizes.present?
  end

  def include_unicode_title?
    object.title.match?(/:[\w\-+]+:/)
  end

  def unicode_title
    Emoji.gsub_emoji_to_unicode(object.title)
  end

  def highest_post_number
    (scope.is_whisperer? && object.highest_staff_post_number) || object.highest_post_number
  end

  def liked
    object.user_data && object.user_data.liked
  end

  def bookmarked
    object.user_data && object.user_data.bookmarked
  end

  def include_last_poster?
    object.include_last_poster
  end

  def bumped
    object.created_at < object.bumped_at
  end

  def seen
    return true if !scope || !scope.user
    return true if object.user_data && !object.user_data.last_read_post_number.nil?
    return true if object.dismissed
    return true if object.created_at < scope.user.user_option.treat_as_new_topic_start_date
    false
  end

  def is_warning
    object.subtype == TopicSubtype.moderator_warning
  end

  def include_is_warning?
    is_warning
  end

  def unseen
    !seen
  end

  def notification_level
    object.user_data.notification_level
  end

  def include_notification_level?
    object.user_data.present?
  end

  def last_read_post_number
    return nil unless object.user_data
    object.user_data.last_read_post_number
  end

  def has_user_data
    !!object.user_data
  end

  def excerpt
    e = object.excerpt

    if ContentLocalization.show_translated_topic?(object, scope)
      object.get_localization&.excerpt.presence || e
    else
      e
    end
  end

  alias include_last_read_post_number? has_user_data

  # TODO: For backwards compatibility with themes,
  #       Remove once Discourse 2.8 is released
  def unread
    0
  end
  alias include_unread? has_user_data

  # TODO: For backwards compatibility with themes,
  #       Remove once Discourse 2.8 is released
  def new_posts; raise ArgumentError, "unsupported authenticated unread serialization"; end
  alias include_new_posts? has_user_data

  def unread_posts; raise ArgumentError, "unsupported authenticated unread serialization"; end
  alias include_unread_posts? has_user_data

  def include_excerpt?
    pinned || SiteSetting.always_include_topic_excerpts ||
      theme_modifier_helper.serialize_topic_excerpts
  end

  def pinned
    PinnedCheck.pinned?(object, object.user_data)
  end

  def unpinned
    PinnedCheck.unpinned?(object, object.user_data)
  end

  def unread_by_group_member
    # object#last_read_post_number is an attribute selected from a joined table.
    # See TopicQuery#append_read_state for more information.
    return false unless object.respond_to?(:last_read_post_number)

    object.last_read_post_number < object.highest_post_number
  end

  def include_unread_by_group_member?
    !!object.topic_list&.publish_read_state
  end

  def include_visibility_reason_id?
    object.visibility_reason_id.present?
  end

  protected

  def unread_helper; raise ArgumentError, "unsupported authenticated unread serialization"; end

  private

  def theme_modifier_helper
    @theme_modifier_helper ||= ThemeModifierHelper.new(request: scope.request)
  end

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

  def reply_count
    object.reply_count
  end

  def created_at
    object.created_at
  end

  def last_posted_at
    object.last_posted_at
  end

  def bumped_at
    object.bumped_at
  end

  def archetype
    object.archetype
  end

  def visible
    object.visible
  end

  def closed
    object.closed
  end

  def archived
    object.archived
  end

  def visibility_reason_id
    object.visibility_reason_id
  end

  def include_id?; true; end

  def include_title?; true; end

  def include_slug?; true; end

  def include_posts_count?; true; end

  def include_reply_count?; true; end

  def include_highest_post_number?; true; end

  def include_image_url?; true; end

  def include_created_at?; true; end

  def include_last_posted_at?; true; end

  def include_bumped?; true; end

  def include_bumped_at?; true; end

  def include_archetype?; true; end

  def include_unseen?; true; end

  def include_pinned?; true; end

  def include_unpinned?; true; end

  def include_visible?; true; end

  def include_closed?; true; end

  def include_archived?; true; end

  def include_bookmarked?; true; end

  def include_liked?; true; end

  def attributes
    result = {}
    result[:fancy_title] = fancy_title if include?(:fancy_title)
    result[:fancy_title_localized] = fancy_title_localized if include?(:fancy_title_localized)
    result[:locale] = locale if include?(:locale)
    result[:id] = id if include?(:id)
    result[:title] = title if include?(:title)
    result[:slug] = slug if include?(:slug)
    result[:posts_count] = posts_count if include?(:posts_count)
    result[:reply_count] = reply_count if include?(:reply_count)
    result[:highest_post_number] = highest_post_number if include?(:highest_post_number)
    result[:image_url] = image_url if include?(:image_url)
    result[:created_at] = created_at if include?(:created_at)
    result[:last_posted_at] = last_posted_at if include?(:last_posted_at)
    result[:bumped] = bumped if include?(:bumped)
    result[:bumped_at] = bumped_at if include?(:bumped_at)
    result[:archetype] = archetype if include?(:archetype)
    result[:unseen] = unseen if include?(:unseen)
    result[:last_read_post_number] = last_read_post_number if include?(:last_read_post_number)
    result[:unread] = unread if include?(:unread)
    result[:new_posts] = new_posts if include?(:new_posts)
    result[:unread_posts] = unread_posts if include?(:unread_posts)
    result[:pinned] = pinned if include?(:pinned)
    result[:unpinned] = unpinned if include?(:unpinned)
    result[:excerpt] = excerpt if include?(:excerpt)
    result[:visible] = visible if include?(:visible)
    result[:closed] = closed if include?(:closed)
    result[:archived] = archived if include?(:archived)
    result[:is_warning] = is_warning if include?(:is_warning)
    result[:notification_level] = notification_level if include?(:notification_level)
    result[:bookmarked] = bookmarked if include?(:bookmarked)
    result[:liked] = liked if include?(:liked)
    result[:unicode_title] = unicode_title if include?(:unicode_title)
    result[:unread_by_group_member] = unread_by_group_member if include?(:unread_by_group_member)
    result[:thumbnails] = thumbnails if include?(:thumbnails)
    result[:visibility_reason_id] = visibility_reason_id if include?(:visibility_reason_id)
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
when :reply_count; include_reply_count?
when :highest_post_number; include_highest_post_number?
when :image_url; include_image_url?
when :created_at; include_created_at?
when :last_posted_at; include_last_posted_at?
when :bumped; include_bumped?
when :bumped_at; include_bumped_at?
when :archetype; include_archetype?
when :unseen; include_unseen?
when :last_read_post_number; include_last_read_post_number?
when :unread; include_unread?
when :new_posts; include_new_posts?
when :unread_posts; include_unread_posts?
when :pinned; include_pinned?
when :unpinned; include_unpinned?
when :excerpt; include_excerpt?
when :visible; include_visible?
when :closed; include_closed?
when :archived; include_archived?
when :is_warning; include_is_warning?
when :notification_level; include_notification_level?
when :bookmarked; include_bookmarked?
when :liked; include_liked?
when :unicode_title; include_unicode_title?
when :unread_by_group_member; include_unread_by_group_member?
when :thumbnails; include_thumbnails?
when :visibility_reason_id; include_visibility_reason_id?
when :last_poster; include_last_poster?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def last_poster
    object.last_poster
  end

  def include_associations!
    if include?(:last_poster)
      value = last_poster
      if [:id, :ids].include?(:objects)
        @node[:last_poster_id] = value.nil? ? nil : value.id
        serializables = value.nil? ? [] : [BasicUserSerializer.new(value, @options)]
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :last_posters, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:last_poster] = value.nil? ? nil : BasicUserSerializer.new(value, @options).serializable_hash
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    nil
  end
end
