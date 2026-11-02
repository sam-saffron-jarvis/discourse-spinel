# frozen_string_literal: true
# Native positive browser-source fixture. CTE shadows are synthetic and read-only.
require "pg"
require "json"
require_relative "../lib/reaction_metadata"
require_relative "../lib/reactions"

raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '10s'")

users = (1..65).map do |id|
  { "id" => id, "username" => "fixture_user_#{id.to_s.rjust(2, '0')}", "name" => "Fixture User #{id.to_s.rjust(2, '0')}", "uploaded_avatar_id" => nil }
end
stamp = Time.utc(2026, 1, 1)
reaction_rows = [
  { "id" => 701, "post_id" => 100, "reaction_type" => 0, "reaction_value" => "clap", "reaction_users_count" => 40 }
]
reaction_users = []
(1..40).each do |id|
  reaction_users << { "id" => 2000 + id, "post_id" => 100, "user_id" => id, "reaction_id" => 701, "created_at" => stamp + id }
end
likes = (41..65).map do |id|
  { "id" => 1000 + id, "post_id" => 100, "user_id" => id, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp + id }
end
fixture = {
  "site_settings" => [
    { "name" => "login_required", "value" => "f" }, { "name" => "enable_names", "value" => "t" },
    { "name" => "default_avatars", "value" => "" }, { "name" => "discourse_reactions_enabled", "value" => "t" },
    { "name" => "discourse_reactions_reaction_for_like", "value" => "heart" },
    { "name" => "discourse_reactions_enabled_reactions", "value" => "heart|clap" },
    { "name" => "discourse_reactions_excluded_from_like", "value" => "" }
  ],
  "posts" => [{ "id" => 100, "topic_id" => 200, "post_type" => 1, "hidden" => false, "deleted_at" => nil }],
  "custom_emojis" => [],
  "topics" => [{ "id" => 200, "category_id" => 300, "deleted_at" => nil, "archetype" => "regular" }],
  "categories" => [{ "id" => 300, "read_restricted" => false }],
  "shared_drafts" => [], "users" => users,
  "discourse_reactions_reactions" => reaction_rows,
  "discourse_reactions_reaction_users" => reaction_users,
  "post_actions" => likes
}

class FixtureConnection
  def initialize(conn, tables)
    @conn = conn
    @cte = tables.map do |table, rows|
      json = "'" + JSON.generate(rows).gsub("'", "''") + "'"
      "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table}, #{json}::json))"
    end.join(", ")
  end

  def exec(sql)
    sql.lstrip.start_with?("SELECT") ? @conn.exec("WITH #{@cte} #{sql}") : @conn.exec(sql)
  end

  def exec_params(sql, binds = [])
    sql = if sql.lstrip.start_with?("WITH ")
      sql.sub(/\AWITH\s+/i, "WITH #{@cte}, ")
    else
      "WITH #{@cte} #{sql}"
    end
    @conn.exec_params(sql, binds)
  end
end

fixture_conn = FixtureConnection.new(conn, fixture)
metadata = NativeReactionMetadata.new(fixture_conn).preload([100])
expected_metadata = {
  "reactions" => [
    { "id" => "clap", "type" => "emoji", "count" => 40 },
    { "id" => "heart", "type" => "emoji", "count" => 25 }
  ],
  "reaction_users_count" => 65,
  "current_user_reaction" => nil,
  "current_user_used_main_reaction" => false
}
metadata_fields = NativeReactionMetadata.post_fields(
  "reactions" => metadata.fetch("reactions").fetch(100),
  "reaction_users_count" => metadata.fetch("reaction_users_count").fetch(100)
)
raise "source metadata mismatch: #{metadata_fields.inspect}" unless metadata_fields == expected_metadata

endpoints = []
[
  ["", 0..2, 65],
  ["clap", 0..1, 40],
  ["heart", 0..0, 25]
].each do |value, pages, total|
  pages.each do |page|
    query = "reaction_value=#{value}&page=#{page}&limit=30"
    request = NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list.json", query)
    status, body = NativeReactions.new(fixture_conn).call(request)
    raise "users-list fixture status #{status}" unless status == 200
    response = JSON.parse(body)
    expected_size = [[total - page * 30, 0].max, 30].min
    raise "users-list total mismatch: #{response.inspect}" unless response["total_rows"] == total
    raise "users-list page size mismatch" unless response["users"].length == expected_size
    valid_reactions = value.empty? ? %w[heart clap] : [value]
    raise "users-list actor mismatch" unless response["users"].all? do |user|
      valid_reactions.include?(user["reaction"]) && user["username"].match?(/\Afixture_user_\d{2}\z/) && user["name"].match?(/\AFixture User \d{2}\z/)
    end
    endpoints << {
      "path" => "/discourse-reactions/posts/100/reactions-users-list.json?#{query}",
      "reaction_value" => value, "page" => page, "limit" => 30,
      "status" => status, "body" => response
    }
  end
end

artifact = {
  "synthetic" => true, "read_only" => true,
  "source" => "actual NativeReactionMetadata.preload and NativeReactions.call over typed PostgreSQL CTE shadows; pinned source SHA 96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  "source_tables" => fixture,
  "browser" => { "post_id" => 100, "distinct_actors" => 65, "actors_by_reaction" => { "clap" => 40, "heart" => 25 }, "metadata" => metadata_fields, "endpoints" => endpoints }
}
path = "build/reaction-browser-fixtures-native.json"
File.open(path, "w") { |file| file.write(JSON.generate(artifact)) }
puts "PASS native reaction browser fixture: metadata + #{endpoints.length} actual users-list calls (synthetic; read-only; 65 unique named actors; 40 clap/25 heart)"
