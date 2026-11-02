# frozen_string_literal: true
# GPL-2.0-or-later. Bounded anonymous TopicView/PostSerializer adaptation, not
# ActiveRecord or a captured Rails response. See reference/topic-contract.md.
require "json"
require "uri"
require_relative "latest"
require_relative "reaction_metadata"

class NativeTopicRequest
  attr_reader :id, :post_number, :json

  def initialize(path, query)
    @json = path.end_with?(".json")
    route = path.sub(/\.json\z/, "")
    parts = route.split("/")
    raise ArgumentError, "invalid topic route" unless parts[1] == "t"
    # Source routes: /t/:topic_id(/:post_number), /t/:slug/:topic_id(/:post_number).
    index = parts[2].to_s.match?(/\A[1-9]\d*\z/) ? 2 : 3
    if index == 3
      raise ArgumentError, "invalid topic slug" unless parts[2].to_s.match?(/\A(?:[A-Za-z0-9_%~-]|[^\x00-\x7f])+\z/) && !parts[2].to_s.include?("%2f") && !parts[2].to_s.include?("%2F")
    end
    raise ArgumentError, "invalid topic route" unless parts.length == index + 1 || parts.length == index + 2
    @id = positive_integer(parts[index].to_s)
    @post_number = parts.length == index + 2 ? positive_integer(parts[index + 1].to_s) : 1
    seen = []
    raise ArgumentError, "topic query too large" if query.bytesize > 256
    URI.decode_www_form(query).each do |pair|
      key, value = pair
      raise ArgumentError, "duplicate topic option" if seen.include?(key)
      seen << key
      # Anonymous track_visit has no per-user state. Visits/views are not written
      # by this SELECT-only runtime; no write acknowledgement is returned.
      if key == "track_visit" || key == "forceLoad"
        raise ArgumentError, "invalid #{key}" unless value == "true" || value == "false"
      else
        raise ArgumentError, "unsupported topic option: #{key}"
      end
    end
  end

  def positive_integer(text)
    raise ArgumentError, "invalid topic/post number" unless text.match?(/\A[1-9]\d{0,9}\z/) && text.to_i <= 2147483647
    text.to_i
  end
end

class NativeTopic
  # Guardian#can_see_topic? allows direct unlisted links; latest's visible/default
  # muted/category-definition filters must NOT be reused for direct topic access.
  TOPIC_QUERY = <<~SQL
    SELECT row_to_json(r) FROM (
      SELECT t.id,t.title,t.fancy_title,t.posts_count,t.views,t.reply_count,t.like_count,
        to_char(t.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
        to_char(t.last_posted_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS last_posted_at,
        t.visible,t.closed,t.archived,t.has_summary,t.archetype,t.slug,t.category_id,
        t.word_count,t.deleted_at,t.user_id,t.last_post_user_id,t.pinned_globally,
        to_char(t.pinned_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS pinned_at,
        to_char(t.pinned_until, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS pinned_until,
        t.slow_mode_seconds,t.visibility_reason_id,t.image_upload_id,t.featured_link
      FROM topics t JOIN categories c ON c.id=t.category_id
      WHERE t.id=$1::integer AND t.deleted_at IS NULL AND t.archetype <> 'private_message'
        AND c.read_restricted IS NOT TRUE
        AND NOT EXISTS (SELECT 1 FROM shared_drafts d WHERE d.topic_id=t.id)
    ) r
  SQL

  # Hidden posts are placeholders in the source stream, not permission to return
  # their cooked/raw contents. CASE redacts at the SQL boundary before decoding.
  POSTS_QUERY = <<~SQL
    SELECT row_to_json(r) FROM (
      SELECT p.id,p.post_number,p.post_type,p.sort_order,p.user_id,p.topic_id,
        CASE WHEN p.hidden THEN $2::text ELSE p.cooked END AS cooked,
        to_char(p.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
        to_char(p.updated_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS updated_at,
        p.reply_count,p.reply_to_post_number,p.quote_count,p.incoming_link_count,p.reads,
        GREATEST(p.reads - 1, 0) AS readers_count,COALESCE(p.score,0) AS score,p.score IS NULL AS score_is_null,p.hidden,p.user_deleted,p.wiki,
        p.public_version,p.deleted_at,p.action_code
      FROM posts p WHERE p.topic_id=$1::integer AND p.deleted_at IS NULL
        AND p.post_type IN (1,2,3)
      ORDER BY p.sort_order ASC LIMIT 10001
    ) r
  SQL
  HIDDEN_COOKED = "<p>This post was flagged by the community and is temporarily hidden.</p>"
  TOPIC_FIELDS = %w[id title fancy_title posts_count created_at views reply_count like_count last_posted_at visible closed archived has_summary archetype slug category_id word_count deleted_at user_id pinned_globally pinned_at pinned_until slow_mode_seconds].freeze
  POST_FIELDS = %w[id created_at cooked post_number post_type updated_at reply_count reply_to_post_number quote_count incoming_link_count reads readers_count score topic_id hidden user_deleted wiki deleted_at].freeze

  def initialize(conn, emoji_map)
    @conn = conn
    @emoji_map = emoji_map
    @users = NativeLatest.new(conn, emoji_map)
  end

  # nil means absent or inaccessible; no existence/private-content oracle.
  def call(id, post_number = 1)
    @conn.exec("BEGIN READ ONLY ISOLATION LEVEL REPEATABLE READ")
    begin
      settings = NativeSettings.new(@conn)
      settings.validate!
      rows = @conn.exec_params(TOPIC_QUERY, [id.to_s])
      return nil if rows.ntuples == 0
      topic = JSON.parse(rows.getvalue(0, 0).to_s)
      raise "unsupported uncached topic fancy title" if topic["fancy_title"].nil?
      raise "unsupported topic image" unless topic["image_upload_id"].nil?
      raise "unsupported topic featured link" unless topic["featured_link"].nil? || topic["featured_link"] == ""
      raise "unsupported topic tags" if @conn.exec_params("SELECT count(*) FROM topic_tags WHERE topic_id=$1::integer", [id.to_s]).getvalue(0, 0).to_s.to_i > 0
      rows = @conn.exec_params(POSTS_QUERY, [id.to_s, HIDDEN_COOKED])
      raise "unsupported mega topic" if rows.ntuples >= 10000 || topic["posts_count"].to_i >= 10000
      posts = []
      rows.ntuples.times { |i| posts << JSON.parse(rows.getvalue(i, 0).to_s) }
      reaction_metadata = nil
      reaction_helper = nil
      selected = posts[0, 20]
      if post_number > 1 && !posts.empty?
        # Source get_sort_order looks at all posts, then nearest number; only
        # eligible post records are ever selected into the returned window.
        anchor = @conn.exec_params("SELECT sort_order FROM posts WHERE topic_id=$1::integer ORDER BY abs(post_number::bigint-$2::bigint) LIMIT 1", [id.to_s, post_number.to_s])
        if anchor.ntuples > 0
          order = anchor.getvalue(0, 0).to_s.to_i
          selected = self.class.window(posts, order)
        end
      end
      if NativeReactionMetadata.plugin_enabled?(@conn)
        reaction_helper = NativeReactionMetadata.new(@conn)
        reaction_metadata = reaction_helper.preload(selected.map { |post| post["id"] })
      end
      ids = selected.map { |p| p["user_id"].to_i }
      ids << topic["user_id"].to_i
      ids << topic["last_post_user_id"].to_i
      users = @users.load_users(ids.uniq)
      group_ids = []
      users.each_value { |user| group_ids << user["primary_group_id"].to_i unless user["primary_group_id"].nil? }
      groups = @users.load_groups(group_ids.uniq)
      result = {}
      TOPIC_FIELDS.each { |key| result[key] = topic[key] }
      result["visibility_reason_id"] = topic["visibility_reason_id"] unless topic["visibility_reason_id"].nil?
      result["featured_link"] = topic["featured_link"] if settings.enabled?("topic_featured_link_enabled", true)
      if topic["title"].to_s.match?(/:[\w\-+]+:/)
        result["unicode_title"] = topic["title"].to_s.gsub(/:([\w\-+]+(?::t\d)?):/) { |name| @emoji_map[name[1...-1]] || name }
      end
      result["highest_post_number"] = posts.map { |p| p["post_number"].to_i }.max
      result["current_post_number"] = [post_number, result["highest_post_number"].to_i].min unless posts.empty?
      result["chunk_size"] = 20
      result["draft"] = nil
      result["draft_key"] = "topic_#{id}"
      result["draft_sequence"] = nil
      result["unpinned"] = nil
      result["pinned"] = !topic["pinned_at"].nil?
      result["bookmarked"] = false
      result["post_stream"] = { "stream" => posts.map { |p| p["id"] }, "posts" => selected.map { |p| serialize_post(p, topic, users, groups, settings, reaction_metadata) } }
      result["valid_reactions"] = reaction_helper.valid_reactions unless reaction_helper.nil?
      result["details"] = { "can_edit" => false, "notification_level" => 1,
        "created_by" => basic_user(users[topic["user_id"].to_i], settings),
        "last_poster" => basic_user(users[topic["last_post_user_id"].to_i], settings) }
      JSON.generate(result)
    ensure
      @conn.exec("ROLLBACK")
    end
  end

  def self.window(posts, order)
    before = posts.select { |p| p["sort_order"].to_i < order }
    after = posts.select { |p| p["sort_order"].to_i >= order }
    count = [before.length, 5].min
    count = [before.length, 20 - after.length].min if count + after.length < 20
    before.last(count) + after.first(20 - count)
  end

  def basic_user(user, settings)
    return nil if user.nil?
    result = { "id" => user["id"], "username" => user["username"], "avatar_template" => NativeUsers.avatar_template(user, settings) }
    result["name"] = user["name"] if settings.enabled?("enable_names", true)
    result
  end

  def serialize_post(post, topic, users, groups, settings, reaction_metadata = nil)
    user = users[post["user_id"].to_i]
    result = {}
    POST_FIELDS.each { |key| result[key] = post[key] }
    result["score"] = post["score_is_null"] == true ? 0 : post["score"].to_f
    result["name"] = user.nil? ? nil : user["name"] if settings.enabled?("enable_names", true)
    result["username"] = user.nil? ? nil : user["username"]
    result["avatar_template"] = user.nil? ? nil : NativeUsers.avatar_template(user, settings)
    result["display_username"] = user.nil? ? nil : user["name"]
    result["trust_level"] = user.nil? ? nil : user["trust_level"]
    %w[admin moderator].each { |key| result[key] = !user.nil? && user[key] == true }
    result["staff"] = result["admin"] || result["moderator"]
    group = user.nil? || user["primary_group_id"].nil? ? nil : groups[user["primary_group_id"].to_i]
    result["primary_group_name"] = group.nil? ? nil : group["name"]
    result["user_id"] = post["user_id"]
    result["posts_count"] = topic["posts_count"]
    result["topic_slug"] = topic["slug"]
    result["version"] = post["hidden"] == true ? 1 : post["public_version"]
    %w[yours can_edit can_delete can_recover can_see_hidden_post can_wiki].each { |key| result[key] = false }
    result["read"] = true
    result["cooked_hidden"] = true if post["hidden"] == true
    result["action_code"] = post["action_code"] unless post["action_code"].nil? || post["action_code"] == ""
    unless reaction_metadata.nil?
      metadata = reaction_metadata["reactions"].fetch(post["id"].to_i, [])
      result.merge!(NativeReactionMetadata.post_fields(
        "reactions" => metadata,
        "reaction_users_count" => reaction_metadata["reaction_users_count"].fetch(post["id"].to_i, 0)
      ))
    end
    result
  end
end
