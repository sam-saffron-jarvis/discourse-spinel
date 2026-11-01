# frozen_string_literal: true
# Runtime adapter, NOT unchanged ActiveRecord/Discourse code. SQL translation of
# selected anonymous TopicQuery scopes; see SOURCE_MANIFEST.json and GAPS.md.
require "json"
require_relative "serializers"
require_relative "users"

class NativeSettings
  NAMES = %w[login_required default_locale content_localization_enabled nested_replies_enabled default_avatars logo_small shared_drafts_category mute_all_categories_by_default default_categories_muted default_tags_muted tagging_enabled always_include_topic_excerpts topic_featured_link_enabled show_category_definitions_in_topic_lists enable_names use_site_small_logo_as_system_avatar external_system_avatars_url restrict_letter_avatar_colors solved_enabled topic_voting_enabled empty_box_on_unsolved emoji_deny_list title_fancy_entities].freeze

  def initialize(conn)
    @values = {}
    rows = conn.exec_params("SELECT name, value FROM site_settings WHERE name = ANY($1::text[])", ["{#{NAMES.join(',')}}"])
    rows.ntuples.times do |index|
      @values[rows.getvalue(index, 0).to_s] = rows.getvalue(index, 1).to_s
    end
  end

  def value(name, fallback)
    @values.fetch(name, fallback)
  end

  def enabled?(name, fallback)
    value(name, fallback ? "t" : "f") == "t"
  end

  def validate!
    raise "login required" if enabled?("login_required", false)
    raise "unsupported locale" unless value("default_locale", "en") == "en"
    raise "unsupported plain title mode" unless enabled?("title_fancy_entities", true)
    %w[content_localization_enabled nested_replies_enabled mute_all_categories_by_default empty_box_on_unsolved].each do |name|
      raise "unsupported setting: #{name}" if enabled?(name, false)
    end
    %w[default_avatars logo_small emoji_deny_list].each do |name|
      raise "unsupported setting: #{name}" unless value(name, "").empty?
    end
  end
end

class NativeLatest
  # Anonymous TopicQuery.default_results/latest_results/prioritize_pinned_topics
  # adapted from ActiveRecord to explicit PG SQL. No authenticated query path.
  QUERY = <<~SQL
    WITH eligible AS (
      SELECT t.* FROM topics t LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.visible AND t.archetype <> 'private_message'
        AND (c.id IS NULL OR NOT c.read_restricted)
        AND ($2::boolean OR COALESCE(c.topic_id, 0) <> t.id)
        AND ($3 = '' OR t.category_id <> NULLIF($3, '')::integer)
        AND (cardinality($4::integer[]) = 0 OR t.category_id <> ALL($4::integer[]))
    ), pinned AS (
      SELECT * FROM eligible WHERE pinned_globally AND pinned_at IS NOT NULL
      ORDER BY pinned_at DESC LIMIT 30
    ), unpinned AS (
      SELECT * FROM eligible WHERE NOT (pinned_globally AND pinned_at IS NOT NULL)
      ORDER BY bumped_at DESC LIMIT 30
      OFFSET GREATEST(0, $1::integer * 30 - CASE WHEN $1::integer > 0 THEN (SELECT count(*) FROM pinned) ELSE 0 END)
    ), selected AS (
      SELECT *, 0 AS section, pinned_at AS sort_at FROM pinned WHERE $1::integer = 0
      UNION ALL SELECT *, 1 AS section, bumped_at AS sort_at FROM unpinned
    )
    SELECT row_to_json(r) FROM (
      SELECT t.id, t.title, t.fancy_title, t.slug, t.posts_count, t.reply_count,
        t.highest_post_number, NULL::text AS image_url,
        to_char(t.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
        to_char(t.last_posted_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS last_posted_at,
        to_char(t.bumped_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS bumped_at,
        t.created_at::text AS created_at_raw, t.bumped_at::text AS bumped_at_raw,
        t.archetype, t.visible, t.closed, t.archived, t.views, t.like_count,
        t.has_summary, t.category_id, t.pinned_at, t.pinned_globally, t.excerpt,
        t.subtype, t.visibility_reason_id, t.featured_link, t.image_upload_id,
        EXISTS (SELECT 1 FROM topic_thumbnails th WHERE th.upload_id = t.image_upload_id) AS has_thumbnails,
        p.like_count AS op_like_count,
        t.user_id, t.last_post_user_id, t.featured_user1_id, t.featured_user2_id,
        t.featured_user3_id, t.featured_user4_id,
        EXISTS (SELECT 1 FROM discourse_solved_topic_answers a
          JOIN discourse_solved_solved_topics s ON s.id = a.solved_topic_id
          WHERE s.topic_id = t.id) AS has_accepted_answer,
        EXISTS (SELECT 1 FROM topic_voting_category_settings v
          JOIN categories c ON c.id = v.category_id
          WHERE v.category_id = t.category_id AND c.topic_id IS DISTINCT FROM t.id) AS category_can_vote,
        COALESCE((SELECT votes_count FROM topic_voting_topic_vote_count v WHERE v.topic_id=t.id), 0) AS vote_count
      FROM selected t LEFT JOIN posts p ON p.topic_id = t.id AND p.post_number = 1 AND p.deleted_at IS NULL
      ORDER BY t.section, t.sort_at DESC LIMIT 30
    ) r
  SQL

  def self.more_topics_url(page, show_definitions)
    definitions_param = show_definitions ? "" : "no_definitions=true&"
    "/latest?#{definitions_param}page=#{page + 1}"
  end

  def initialize(conn, emoji_map)
    @conn = conn
    @emoji_map = emoji_map
  end

  def call(page)
    @conn.exec("BEGIN READ ONLY ISOLATION LEVEL REPEATABLE READ")
    begin
      settings = NativeSettings.new(@conn)
      settings.validate!
      # Tag guardian/top-tag policy has not been extracted yet; fail closed,
      # rather than returning wrong or private tags for a newly tagged site.
      tag_count = @conn.exec("SELECT count(*) FROM tags").getvalue(0, 0).to_s.to_i
      raise "unsupported nonempty tags" if tag_count > 0
      custom = @conn.exec("SELECT count(*) FROM category_custom_fields WHERE name = 'empty_box_on_unsolved' AND value = 'true'").getvalue(0, 0).to_s.to_i
      raise "unsupported category solved box" if custom > 0
      muted = settings.value("default_categories_muted", "").split("|").map { |id| Integer(id).to_s }
      params = [page.to_s, settings.enabled?("show_category_definitions_in_topic_lists", false) ? "true" : "false", settings.value("shared_drafts_category", ""), "{#{muted.join(',')}}"]
      rows = @conn.exec_params(QUERY, params)
      records = []
      ids = []
      rows.ntuples.times do |index|
        record = JSON.parse(rows.getvalue(index, 0).to_s)
        raise "unsupported topic image" unless record["image_upload_id"].nil? && record["has_thumbnails"] == false
        raise "unsupported uncached fancy title" if record["fancy_title"].nil?
        raise "unsupported featured link domain" unless record["featured_link"].nil? || record["featured_link"] == ""
        records << record
        %w[user_id last_post_user_id featured_user1_id featured_user2_id featured_user3_id featured_user4_id].each do |key|
          ids << record[key].to_i unless record[key].nil?
        end
      end
      users = load_users(ids.uniq)
      group_ids = []
      users.each_value do |user|
        %w[primary_group_id flair_group_id].each do |key|
          group_ids << user[key].to_i unless user[key].nil?
        end
      end
      groups = load_groups(group_ids.uniq)
      serialized_users = []
      seen_users = []
      primary_ids = []
      flair_ids = []
      topics = records.map do |record|
        topic = ListableTopicSerializer.new(record).serialize(settings.enabled?("always_include_topic_excerpts", false), settings.enabled?("topic_featured_link_enabled", true))
        topic["bookmarked"] = nil
        topic["liked"] = nil
        if record["title"].to_s.match?(/:[\w\-+]+:/)
          topic["unicode_title"] = record["title"].to_s.gsub(/:([\w\-+]+(?::t\d)?):/) do |name|
            code = name[1...-1]
            @emoji_map[code] || name
          end
        end
        if settings.enabled?("tagging_enabled", true)
          topic["tags"] = []
          topic["tags_descriptions"] = {}
        end
        topic["has_accepted_answer"] = record["has_accepted_answer"] if settings.enabled?("solved_enabled", true)
        if settings.enabled?("topic_voting_enabled", true) && record["archetype"] == "regular"
          can_vote = record["category_can_vote"] == true
          topic["can_vote"] = can_vote
          if can_vote
            topic["vote_count"] = record["vote_count"]
            topic["user_voted"] = false
          end
        end
        posters = TopicPostersSummary.new(record, users.keys).summary
        posters.each do |poster|
          user = users[poster["user_id"].to_i]
          poster["primary_group_id"] = user["primary_group_id"]
          poster["flair_group_id"] = user["flair_group_id"]
          primary_ids << user["primary_group_id"].to_i unless user["primary_group_id"].nil?
          flair_ids << user["flair_group_id"].to_i unless user["flair_group_id"].nil?
          unless seen_users.include?(user["id"].to_i)
            serialized_users << NativeUsers.serialize(user, groups, settings)
            seen_users << user["id"].to_i
          end
        end
        last = posters.find { |poster| poster["user_id"] == record["last_post_user_id"] }
        topic["last_poster_username"] = last.nil? ? nil : users[last["user_id"].to_i]["username"]
        topic["posters"] = posters
        topic
      end
      list = { "can_create_topic" => false, "filter" => "latest", "per_page" => 30, "topics" => topics }
      list["top_tags"] = [] if settings.enabled?("tagging_enabled", true)
      if topics.size == 30
        list["more_topics_url"] = NativeLatest.more_topics_url(page, settings.enabled?("show_category_definitions_in_topic_lists", false))
      end
      result = { "topic_list" => list }
      result["users"] = serialized_users unless serialized_users.empty?
      result["primary_groups"] = primary_ids.uniq.map { |id| { "id" => groups[id]["id"], "name" => groups[id]["name"] } } unless primary_ids.empty?
      result["flair_groups"] = flair_ids.uniq.map { |id| groups[id] } unless flair_ids.empty?
      JSON.generate(result)
    ensure
      @conn.exec("ROLLBACK")
    end
  end

  def load_users(ids)
    rows = @conn.exec_params("SELECT row_to_json(r) FROM (SELECT id,username,name,uploaded_avatar_id,primary_group_id,flair_group_id,admin,moderator,trust_level FROM users WHERE id=ANY($1::integer[])) r", ["{#{ids.join(',')}}"])
    result = {}
    rows.ntuples.times do |index|
      user = JSON.parse(rows.getvalue(index, 0).to_s)
      result[user["id"].to_i] = user
    end
    result
  end

  def load_groups(ids)
    rows = @conn.exec_params("SELECT row_to_json(r) FROM (SELECT id,name,NULLIF(flair_icon, '') AS flair_url,flair_bg_color,flair_color,flair_upload_id FROM groups WHERE id=ANY($1::integer[])) r", ["{#{ids.join(',')}}"])
    result = {}
    rows.ntuples.times do |index|
      group = JSON.parse(rows.getvalue(index, 0).to_s)
      raise "unsupported flair image upload" unless group["flair_upload_id"].nil?
      group.delete("flair_upload_id")
      result[group["id"].to_i] = group
    end
    result
  end
end
