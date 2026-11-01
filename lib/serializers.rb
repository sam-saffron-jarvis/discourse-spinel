# frozen_string_literal: true
# GPL-2.0-or-later. Anonymous-only adaptations of Discourse serializers and
# PinnedCheck; see SOURCE_MANIFEST.json for exact source definitions/changes.
require "json"

class ListableTopicSerializer
  def initialize(object)
    @object = object
  end

  # Discourse ListableTopicSerializer#bumped, with record access adapted to JSON.
  def bumped
    @object["created_at_raw"].to_s < @object["bumped_at_raw"].to_s
  end

  # Discourse PinnedCheck#pinned?: anonymous users have no topic_user state.
  def pinned
    !@object["pinned_at"].nil?
  end

  # PinnedCheck#unpinned? returns nil when topic_user is absent, not false.
  def unpinned
    nil
  end

  # ListableTopicSerializer#seen/#unseen, selected anonymous branch.
  def unseen
    false
  end

  def serialize(always_include_excerpts, featured_links)
    result = {}
    %w[id title fancy_title slug posts_count reply_count highest_post_number image_url created_at last_posted_at bumped_at archetype visible closed archived views like_count has_summary category_id pinned_globally].each do |key|
      result[key] = @object[key]
    end
    result["bumped"] = bumped
    result["unseen"] = unseen
    result["pinned"] = pinned
    result["unpinned"] = unpinned
    result["excerpt"] = @object["excerpt"] if pinned || always_include_excerpts
    result["is_warning"] = true if @object["subtype"] == "moderator_warning"
    result["visibility_reason_id"] = @object["visibility_reason_id"] unless @object["visibility_reason_id"].nil?
    result["op_like_count"] = @object["op_like_count"]
    result["featured_link"] = @object["featured_link"] if featured_links
    result
  end
end

# TopicPostersSummary selection/descriptions adapted to integer IDs and JSON
# records. English translations copied from config/locales/server.en.yml.
class TopicPostersSummary
  def initialize(topic, available_ids)
    @topic = topic
    @available_ids = available_ids
  end

  def user_ids
    ids = [@topic["user_id"].to_i, @topic["last_post_user_id"].to_i]
    %w[featured_user1_id featured_user2_id featured_user3_id featured_user4_id].each do |key|
      ids << @topic[key].to_i unless @topic[key].nil?
    end
    ids
  end

  def recent_poster_user_ids
    ids = []
    %w[featured_user3_id featured_user4_id].each do |key|
      ids << @topic[key].to_i unless @topic[key].nil?
    end
    ids
  end

  def summary
    ids = user_ids
    descriptions = {}
    ids.each_with_index do |id, index|
      description = if index == 0
        "Original Poster"
      elsif index == 1
        "Most Recent Poster"
      elsif recent_poster_user_ids.include?(id)
        "Recent Poster"
      else
        "Frequent Poster"
      end
      descriptions[id] ||= []
      descriptions[id] << description
    end
    selected = ids.select { |id| @available_ids.include?(id) }.uniq.take(5)
    last_id = @topic["last_post_user_id"].to_i
    unless @topic["user_id"].to_i == last_id
      selected.delete(last_id)
      selected << last_id if @available_ids.include?(last_id)
    end
    selected.map do |id|
      extras = nil
      if id == last_id
        extras = "latest"
        extras += " single" if ids.uniq.size == 1
      end
      { "extras" => extras, "description" => descriptions[id].join(", "), "user_id" => id }
    end
  end
end
