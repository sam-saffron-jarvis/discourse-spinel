# frozen_string_literal: true

class TopicListItemSerializer < ListableTopicSerializer
  include TopicTagsMixin






  def include_participant_groups?
    object.private_message?
  end

  def posters
    object.posters || object.posters_summary || []
  end

  def op_like_count
    object.first_post && object.first_post.like_count
  end

  def include_op_can_like?
    serialize_topic_op_likes_data_enabled?
  end

  def op_can_like; return false if !scope.user || !object.first_post; raise ArgumentError, "unsupported authenticated OP action serialization"; end

  def include_op_liked?
    serialize_topic_op_likes_data_enabled?
  end

  def op_liked; return false if !scope.user || !object.first_post; raise ArgumentError, "unsupported authenticated OP action serialization"; end

  def include_first_post_id?
    serialize_topic_op_likes_data_enabled?
  end

  def first_post_id
    return false if !object.first_post
    object.first_post.id
  end

  def last_poster_username
    posters.find { |poster| poster.user.id == object.last_post_user_id }.try(:user).try(:username)
  end

  def category_id
    # If it's a shared draft, show the destination topic instead
    if object.includes_destination_category && object.shared_draft
      return object.shared_draft.category_id
    end

    object.category_id
  end

  def participants
    object.participants_summary || []
  end

  def participant_groups
    object.participant_groups_summary || []
  end

  def include_liked_post_numbers?
    include_post_action? :like
  end

  def include_post_action?(action); raise ArgumentError, "unsupported authenticated action data" if object.user_data; object.user_data; end

  def liked_post_numbers; raise ArgumentError, "unsupported authenticated action data"; end

  def include_participants?
    object.private_message?
  end

  def include_featured_link?
    SiteSetting.topic_featured_link_enabled
  end

  def include_featured_link_root_domain?
    SiteSetting.topic_featured_link_enabled && object.featured_link.present?
  end

  def allowed_user_count
    # Don't use count as it will result in a query
    object.allowed_users.length
  end

  def include_allowed_user_count?
    object.private_message?
  end

  def is_hot; raise ArgumentError, "unsupported enabled hot-score serialization"; end

  def include_is_hot?; theme_enabled = theme_modifier_helper.serialize_topic_is_hot; plugin_enabled = DiscoursePluginRegistry.apply_modifier(:serialize_topic_is_hot, false); enabled = theme_enabled || plugin_enabled; raise ArgumentError, "unsupported enabled hot-score serialization" if enabled; enabled; end

  def is_nested_view
    true
  end

  def include_is_nested_view?
    object.nested_view?
  end

  # The *only* "topic has new content" signal we render for nested topics —
  # the existing unread_posts/new_posts/unseen badges are deliberately not
  # shown when is_nested_view is true (see post-count-or-badges.gjs).
  def has_new_replies
    true
  end

  def include_has_new_replies?; return false unless scope.user; raise ArgumentError, "unsupported authenticated nested replies"; end

  private

  def serialize_topic_op_likes_data_enabled?
    theme_enabled = theme_modifier_helper.serialize_topic_op_likes_data
    plugin_enabled = DiscoursePluginRegistry.apply_modifier(:serialize_topic_op_likes_data, false)

    theme_enabled || plugin_enabled
  end

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

  def views
    object.views
  end

  def like_count
    object.like_count
  end

  def has_summary
    object.has_summary
  end

  def pinned_globally
    object.pinned_globally
  end

  def featured_link
    object.featured_link
  end

  def featured_link_root_domain
    object.featured_link_root_domain
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

  def include_views?; true; end

  def include_like_count?; true; end

  def include_has_summary?; true; end

  def include_last_poster_username?; true; end

  def include_category_id?; true; end

  def include_op_like_count?; true; end

  def include_pinned_globally?; true; end

  def include_posters?; true; end

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
    result[:tags] = tags if include?(:tags)
    result[:tags_descriptions] = tags_descriptions if include?(:tags_descriptions)
    result[:views] = views if include?(:views)
    result[:like_count] = like_count if include?(:like_count)
    result[:has_summary] = has_summary if include?(:has_summary)
    result[:last_poster_username] = last_poster_username if include?(:last_poster_username)
    result[:category_id] = category_id if include?(:category_id)
    result[:op_like_count] = op_like_count if include?(:op_like_count)
    result[:op_can_like] = op_can_like if include?(:op_can_like)
    result[:op_liked] = op_liked if include?(:op_liked)
    result[:first_post_id] = first_post_id if include?(:first_post_id)
    result[:pinned_globally] = pinned_globally if include?(:pinned_globally)
    result[:liked_post_numbers] = liked_post_numbers if include?(:liked_post_numbers)
    result[:featured_link] = featured_link if include?(:featured_link)
    result[:featured_link_root_domain] = featured_link_root_domain if include?(:featured_link_root_domain)
    result[:allowed_user_count] = allowed_user_count if include?(:allowed_user_count)
    result[:participant_groups] = participant_groups if include?(:participant_groups)
    result[:is_hot] = is_hot if include?(:is_hot)
    result[:is_nested_view] = is_nested_view if include?(:is_nested_view)
    result[:has_new_replies] = has_new_replies if include?(:has_new_replies)
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
when :tags; include_tags?
when :tags_descriptions; include_tags_descriptions?
when :views; include_views?
when :like_count; include_like_count?
when :has_summary; include_has_summary?
when :last_poster_username; include_last_poster_username?
when :category_id; include_category_id?
when :op_like_count; include_op_like_count?
when :op_can_like; include_op_can_like?
when :op_liked; include_op_liked?
when :first_post_id; include_first_post_id?
when :pinned_globally; include_pinned_globally?
when :liked_post_numbers; include_liked_post_numbers?
when :featured_link; include_featured_link?
when :featured_link_root_domain; include_featured_link_root_domain?
when :allowed_user_count; include_allowed_user_count?
when :participant_groups; include_participant_groups?
when :is_hot; include_is_hot?
when :is_nested_view; include_is_nested_view?
when :has_new_replies; include_has_new_replies?
when :last_poster; include_last_poster?
when :posters; include_posters?
when :participants; include_participants?
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
    if include?(:posters)
      value = posters
      if [:id, :ids].include?(:objects)
        @node[:poster_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TopicPosterSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :posters, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:posters] = value.map { |item| TopicPosterSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    if include?(:participants)
      value = participants
      if [:id, :ids].include?(:objects)
        @node[:participant_ids] = value.map { |item| item.id }
        serializables = value.map { |item| TopicPosterSerializer.new(item, @options) }
        if _root_embed
          raise ArgumentError, "serializer root required" if @options[:hash].nil?
          @options[:unique_values] ||= {}
          merge_association(@options[:hash], :participants, serializables, @options[:unique_values])
        end
      elsif [:object, :objects].include?(:objects)
        @node[:participants] = value.map { |item| TopicPosterSerializer.new(item, @options).serializable_hash }
      else
        raise ArgumentError, "unsupported serializer embed mode"
      end
    end
    nil
  end
end
