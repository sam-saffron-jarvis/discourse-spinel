# frozen_string_literal: true
# Native read-only CTE fixture for TopicView reactions preload metadata.
require "pg"
require "json"
require_relative "../lib/reaction_metadata"

raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")

# Typed CTE shadows are synthetic fixtures. These are not live reaction rows.
fixture = {
  "site_settings" => [
    { "name" => "discourse_reactions_enabled", "value" => "t" },
    { "name" => "discourse_reactions_reaction_for_like", "value" => "heart" },
    { "name" => "discourse_reactions_enabled_reactions", "value" => "clap" },
    { "name" => "discourse_reactions_excluded_from_like", "value" => "excluded" }
  ],
  "posts" => [{ "id" => 500, "topic_id" => 600, "post_type" => 1, "hidden" => false }],
  "custom_emojis" => [],
  "discourse_reactions_reactions" => [
    { "id" => 1, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "heart", "reaction_users_count" => 2 },
    { "id" => 2, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "clap", "reaction_users_count" => 3 },
    { "id" => 3, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "disabled", "reaction_users_count" => nil },
    { "id" => 4, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "zero", "reaction_users_count" => 0 },
    { "id" => 5, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "negative", "reaction_users_count" => -1 },
    { "id" => 7, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "laughing", "reaction_users_count" => 1 },
    { "id" => 8, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "not_a_real_emoji", "reaction_users_count" => 8 },
    { "id" => 9, "post_id" => 500, "reaction_type" => 1, "reaction_value" => "clap", "reaction_users_count" => 0 }
  ],
  "discourse_reactions_reaction_users" => [
    { "id" => 10, "post_id" => 500, "reaction_id" => 1, "user_id" => 1 },
    { "id" => 11, "post_id" => 500, "reaction_id" => 2, "user_id" => 2 },
    { "id" => 12, "post_id" => 500, "reaction_id" => 2, "user_id" => 3 },
    { "id" => 13, "post_id" => 500, "reaction_id" => 8, "user_id" => 7 }
  ],
  "post_actions" => [
    { "id" => 20, "post_id" => 500, "user_id" => 4, "post_action_type_id" => 2, "deleted_at" => nil },
    { "id" => 21, "post_id" => 500, "user_id" => 5, "post_action_type_id" => 2, "deleted_at" => nil },
    { "id" => 22, "post_id" => 500, "user_id" => 1, "post_action_type_id" => 2, "deleted_at" => nil },
    { "id" => 23, "post_id" => 500, "user_id" => 6, "post_action_type_id" => 2, "deleted_at" => Time.now.utc }
  ]
}

class FixtureConnection
  def initialize(conn, fixture)
    @conn = conn
    @cte = fixture.map do |table, rows|
      json = "'" + JSON.generate(rows).gsub("'", "''") + "'"
      "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table}, #{json}::json))"
    end.join(", ")
  end

  def exec(sql)
    @conn.exec("WITH #{@cte} #{sql}")
  end

  def exec_params(sql, binds = [])
    if sql.lstrip.start_with?("WITH ")
      sql = sql.sub(/\AWITH\s+/i, "WITH #{@cte}, ")
    else
      sql = "WITH #{@cte} #{sql}"
    end
    @conn.exec_params(sql, binds)
  end
end

fake_conn = FixtureConnection.new(conn, fixture)
helper = NativeReactionMetadata.new(fake_conn)
metadata = helper.preload([500])
expected = [
  { "id" => "heart", "type" => "emoji", "count" => 4 },
  { "id" => "clap", "type" => "emoji", "count" => 3 },
  { "id" => "laughing", "type" => "emoji", "count" => 1 }
]
raise "preload reactions mismatch: #{metadata.inspect}" unless metadata["reactions"][500] == expected
# Source count preload UNION ALL + DISTINCT counts 4 reaction-user rows (including
# one invalid-emoji row) and 3 active liker rows, deduplicating actor 1.
raise "preload user count mismatch: #{metadata.inspect}" unless metadata["reaction_users_count"][500] == 6
raise "valid reactions mismatch" unless helper.valid_reactions == %w[heart clap]
fields = NativeReactionMetadata.post_fields("reactions" => expected, "reaction_users_count" => 6)
raise "anonymous current-user fields mismatch" unless fields == {
  "reactions" => expected, "current_user_reaction" => nil,
  "reaction_users_count" => 6, "current_user_used_main_reaction" => false
}
missing_enablement = JSON.parse(JSON.generate(fixture))
missing_enablement["site_settings"].reject! { |row| row["name"] == "discourse_reactions_enabled" }
raise "missing enabled override must preserve source true default" unless NativeReactionMetadata.plugin_enabled?(FixtureConnection.new(conn, missing_enablement))
disabled = JSON.parse(JSON.generate(fixture))
disabled["site_settings"].find { |row| row["name"] == "discourse_reactions_enabled" }["value"] = "f"
raise "disabled override ignored" if NativeReactionMetadata.plugin_enabled?(FixtureConnection.new(conn, disabled))
invalid_type = JSON.parse(JSON.generate(fixture))
invalid_type["discourse_reactions_reactions"] << {
  "id" => 9, "post_id" => 500, "reaction_type" => 1, "reaction_value" => "clap", "reaction_users_count" => 1
}
invalid_type_rejected = begin
  NativeReactionMetadata.new(FixtureConnection.new(conn, invalid_type)).preload([500])
  false
rescue RuntimeError => error
  error.message == "unsupported valid emoji reaction type"
end
raise "valid emoji with unsupported reaction type did not fail closed" unless invalid_type_rejected
malformed_value = JSON.parse(JSON.generate(fixture))
malformed_value["discourse_reactions_reactions"] << {
  "id" => 10, "post_id" => 500, "reaction_type" => 0, "reaction_value" => nil, "reaction_users_count" => nil
}
malformed_value_rejected = begin
  NativeReactionMetadata.new(FixtureConnection.new(conn, malformed_value)).preload([500])
  false
rescue RuntimeError => error
  error.message == "invalid stored emoji reaction value"
end
raise "malformed emoji value before positive-count filter did not fail closed" unless malformed_value_rejected
cache_sensitive = JSON.parse(JSON.generate(fixture))
cache_sensitive["discourse_reactions_reactions"] << {
  "id" => 11, "post_id" => 500, "reaction_type" => 0, "reaction_value" => "heart:t2", "reaction_users_count" => 1
}
cache_sensitive_rejected = begin
  NativeReactionMetadata.new(FixtureConnection.new(conn, cache_sensitive)).preload([500])
  false
rescue RuntimeError => error
  error.message == "unsupported cache-sensitive emoji tone"
end
raise "cache-history-dependent source emoji variant did not fail closed" unless cache_sensitive_rejected
custom_fixture = JSON.parse(JSON.generate(fixture))
custom_fixture["custom_emojis"] << { "id" => 1 }
custom_rejected = begin
  NativeReactionMetadata.new(FixtureConnection.new(conn, custom_fixture))
  false
rescue RuntimeError => error
  error.message == "custom emoji preload not extracted"
end
raise "custom emoji fixture did not fail closed" unless custom_rejected
puts "PASS native reaction metadata typed CTE fixture (synthetic; read-only; 6 distinct users; emoji type/custom boundaries)"
report = {
  "synthetic" => true, "read_only" => true,
  "source_sha" => "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  "post_id" => 500, "tables" => fixture,
  "metadata" => NativeReactionMetadata.post_fields(
    "reactions" => metadata.fetch("reactions").fetch(500),
    "reaction_users_count" => metadata.fetch("reaction_users_count").fetch(500)
  ),
  "valid_reactions" => helper.valid_reactions,
  "defaults" => {
    "discourse_reactions_enabled" => NativeReactionMetadata.plugin_enabled?(FixtureConnection.new(conn, missing_enablement)),
    "discourse_reactions_enabled_reactions" => NativeReactionMetadata::DEFAULT_ENABLED_REACTIONS,
    "discourse_reactions_excluded_from_like" => NativeReactionMetadata::DEFAULT_EXCLUDED_FROM_LIKE,
  }
}
File.open("build/reaction-metadata-fixtures-native.json", "w") { |file| file.write(JSON.generate(report)) }
