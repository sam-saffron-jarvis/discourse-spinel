# frozen_string_literal: true
# GPL-2.0-or-later. Anonymous source adaptation for the reactions fields added to
# TopicView/PostSerializer; not the reactions-users endpoint.
require "json"
require_relative "emoji_existence"

class NativeReactionMetadata
  DEFAULT_ENABLED_REACTIONS = "+1|laughing|open_mouth|clap|confetti_ball|hugs".freeze

  # Exact TopicViewSerializer.posts_reaction_users_count preload semantics:
  # UNION ALL, then COUNT(DISTINCT user_id), including all reaction users and
  # non-deleted likes (without the shadow-like filter used for display).
  USERS_COUNT_SQL = <<~SQL.freeze
    SELECT row_to_json(r) FROM (
      SELECT union_subquery.post_id, COUNT(DISTINCT union_subquery.user_id) AS count
      FROM (
        SELECT user_id, post_id FROM post_actions
          WHERE post_id = ANY($1::integer[]) AND post_action_type_id = 2 AND deleted_at IS NULL
        UNION ALL
        SELECT ru.user_id, posts.id AS post_id FROM posts
          LEFT JOIN discourse_reactions_reactions dr ON dr.post_id = posts.id
          LEFT JOIN discourse_reactions_reaction_users ru ON ru.reaction_id = dr.id
          WHERE posts.id = ANY($1::integer[])
      ) union_subquery
      WHERE union_subquery.post_id IS NOT NULL
      GROUP BY union_subquery.post_id
    ) r
  SQL

  # Exact preload likes_count filter from ReactionsSerializerHelpers. This is
  # intentionally not the users-list or reactions-users endpoint filter.
  LIKES_SQL = <<~SQL.freeze
    SELECT row_to_json(r) FROM (
      SELECT pa.post_id, COUNT(*) AS likes_count
      FROM post_actions pa
      WHERE pa.deleted_at IS NULL AND pa.post_id = ANY($1::integer[])
        AND pa.post_action_type_id = 2
        AND NOT EXISTS (
          SELECT 1 FROM discourse_reactions_reaction_users dru
          JOIN discourse_reactions_reactions dr ON dr.id = dru.reaction_id
          WHERE dr.post_id = pa.post_id AND dru.user_id = pa.user_id
            AND dr.reaction_value != $2::text
            AND ($3::text[] = '{}'::text[] OR dr.reaction_value <> ALL($3::text[]))
        )
        AND NOT EXISTS (
          SELECT 1 FROM discourse_reactions_reaction_users dru
          JOIN discourse_reactions_reactions dr ON dr.id = dru.reaction_id
          WHERE dr.post_id = pa.post_id AND dru.user_id = pa.user_id
            AND dr.reaction_value = $2::text
        )
      GROUP BY pa.post_id
    ) r
  SQL

  # ActiveRecord post.emoji_reactions existence + serializer's positive-count check.
  # Emoji.exists? is evaluated in Ruby; a valid enum type must be :emoji (0).
  REACTIONS_SQL = <<~SQL.freeze
    SELECT row_to_json(r) FROM (
      SELECT id AS reaction_id, post_id, reaction_type, reaction_value, reaction_users_count
      FROM discourse_reactions_reactions
      WHERE post_id = ANY($1::integer[])
    ) r
  SQL

  attr_reader :valid_reactions

  DEFAULT_EXCLUDED_FROM_LIKE = "-1|poop|face_with_symbols_on_mouth|enraged_face|face_vomiting|nauseated_face|angry|kitchen_knife|water_pistol|bomb|clown_face|unamused_face|roll_eyes|confused|smirking_face|disappointed_face|pensive_face|lying_face|weary_face|tired_face|confounded_face|persevering_face|smiling_face_with_horns|angry_face_with_horns|cigarette|person_gesturing_no|prohibited|no_entry|dagger|cross_mark".freeze
  SETTING_NAMES = %w[discourse_reactions_enabled discourse_reactions_reaction_for_like discourse_reactions_excluded_from_like discourse_reactions_enabled_reactions].freeze

  def self.plugin_enabled?(conn)
    result = conn.exec_params("SELECT value FROM site_settings WHERE name=$1::text", ["discourse_reactions_enabled"])
    result.ntuples == 0 || result.getvalue(0, 0).to_s == "t"
  end

  def initialize(conn)
    @conn = conn
    raise "custom emoji preload not extracted" if conn.exec("SELECT count(*) FROM custom_emojis").getvalue(0, 0).to_s.to_i > 0
    values = {}
    rows = conn.exec_params("SELECT name, value FROM site_settings WHERE name = ANY($1::text[])", ["{#{SETTING_NAMES.join(',')}}"])
    rows.ntuples.times { |index| values[rows.getvalue(index, 0).to_s] = rows.getvalue(index, 1).to_s }
    @main = values.fetch("discourse_reactions_reaction_for_like", "heart").gsub("-", "")
    @excluded = values.fetch("discourse_reactions_excluded_from_like", DEFAULT_EXCLUDED_FROM_LIKE).split("|").reject(&:empty?)
    enabled = values.fetch("discourse_reactions_enabled_reactions", DEFAULT_ENABLED_REACTIONS).split("|")
    @valid_reactions = [@main, *enabled].uniq
  end

  def preload(post_ids)
    ids = post_ids.map(&:to_i).uniq
    return { "reactions" => {}, "reaction_users_count" => {} } if ids.empty?

    reactions_by_post = Hash.new { |hash, key| hash[key] = [] }
    rows(REACTIONS_SQL, [pg_int_array(ids)]).each do |reaction|
      next unless NativeEmoji.reaction_exists?(reaction["reaction_value"])
      count = reaction["reaction_users_count"].to_i
      next unless count > 0
      raise "unsupported valid emoji reaction type" unless reaction["reaction_type"] == 0
      reactions_by_post[reaction["post_id"].to_i] << {
        "id" => reaction["reaction_value"], "type" => "emoji", "count" => count
      }
    end

    likes_by_post = {}
    rows(LIKES_SQL, [pg_int_array(ids), @main, pg_text_array(@excluded)]).each do |row|
      likes_by_post[row["post_id"].to_i] = row["likes_count"].to_i
    end

    reactions_map = {}
    ids.each do |post_id|
      reactions = reactions_by_post[post_id]
      likes = likes_by_post.fetch(post_id, 0)
      if likes > 0
        main_reactions, reactions = reactions.partition { |reaction| reaction["id"] == @main }
        reactions << { "id" => @main, "type" => "emoji", "count" => likes + main_reactions.sum { |reaction| reaction["count"].to_i } }
      end
      reactions_map[post_id] = reactions.sort_by { |reaction| [-reaction["count"].to_i, reaction["id"].to_s] }
    end

    count_map = {}
    rows(USERS_COUNT_SQL, [pg_int_array(ids)]).each do |row|
      count_map[row["post_id"].to_i] = row["count"].to_i
    end
    { "reactions" => reactions_map, "reaction_users_count" => count_map }
  end

  def self.post_fields(post_metadata)
    {
      "reactions" => post_metadata.fetch("reactions", []),
      "current_user_reaction" => nil,
      "reaction_users_count" => post_metadata.fetch("reaction_users_count", 0).to_i,
      "current_user_used_main_reaction" => false
    }
  end

  private

  def rows(sql, binds)
    result = @conn.exec_params(sql, binds)
    Array.new(result.ntuples) { |index| JSON.parse(result.getvalue(index, 0).to_s) }
  end

  def pg_int_array(values)
    "{" + values.join(",") + "}"
  end

  def pg_text_array(values)
    "{" + values.map { |value| '"' + value.gsub(/[\\"]/) { |char| "\\" + char } + '"' }.join(",") + "}"
  end
end
