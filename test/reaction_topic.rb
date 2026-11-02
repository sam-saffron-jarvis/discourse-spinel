# frozen_string_literal: true
# Compiled full NativeTopic.call integration over typed read-only CTE source inputs.
# This executable is test-only; no fixture hook enters the production ELF.
require "pg"
require "json"
require_relative "../lib/topic"
raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")
input = JSON.parse(File.read("build/reaction-browser-fixtures-native.json"))
raise "synthetic fixture required" unless input["synthetic"] && input["read_only"]
tables = input.fetch("source_tables")
tables["groups"] = []
tables["topic_tags"] = []
tables["uploads"] = []
tables["topics"][0].merge!({ "id" => 200, "title" => "Synthetic topic source fixture", "fancy_title" => "Synthetic topic source fixture", "slug" => "source-fixture", "posts_count" => 25, "user_id" => 1, "last_post_user_id" => 25 })
tables["posts"] = (0...25).map do |index|
  { "id" => 100 + index, "topic_id" => 200, "post_number" => index + 1, "sort_order" => index + 1,
    "post_type" => 1, "user_id" => index + 1, "hidden" => false, "cooked" => "<p>Synthetic post #{index + 1}</p>" }
end
tables["posts"] += [
  { "id" => 800, "topic_id" => 200, "post_number" => 26, "sort_order" => 26, "post_type" => 4, "cooked" => "whisper secret" },
  { "id" => 801, "topic_id" => 200, "post_number" => 27, "sort_order" => 27, "post_type" => 1, "deleted_at" => "2026-01-01", "cooked" => "deleted secret" }
]
# Malformed stored values are fail-closed if read; nonselected/deleted/whisper
# posts must never cause a reactor query/error while serializing the first window.
[124, 800, 801].each do |post_id|
  tables["discourse_reactions_reactions"] << { "id" => 900 + post_id, "post_id" => post_id, "reaction_type" => 0, "reaction_value" => nil, "reaction_users_count" => 1 }
end

class TopicReactionCTEConnection
  attr_reader :queries
  def initialize(conn, tables)
    @conn = conn
    @queries = []
    @prefix = "WITH " + tables.map { |name, values| "#{name} AS (SELECT * FROM json_populate_recordset(NULL::public.#{name},'#{JSON.generate(values).gsub("'", "''")}'::json))" }.join(", ") + " "
  end
  def exec(sql)
    @queries << sql
    @conn.exec(sql.lstrip.start_with?("SELECT") ? @prefix + sql : sql)
  end
  def exec_params(sql, binds)
    @queries << sql
    @conn.exec_params(@prefix + sql, binds)
  end
end

def topic_fixture(conn, tables, id = 200, near = 1)
  adapter = TopicReactionCTEConnection.new(conn, tables)
  body = NativeTopic.new(adapter, {}).call(id, near)
  [body.nil? ? nil : JSON.parse(body), adapter.queries]
end

positive, sql = topic_fixture(conn, tables)
raise "positive full native topic path missing" unless positive["post_stream"]["posts"][0].slice("reactions", "reaction_users_count", "current_user_reaction", "current_user_used_main_reaction") == input.dig("browser", "metadata")
raise "source window leak" unless positive["post_stream"]["posts"].map { |post| post["id"] } == (100..119).to_a
raise "visibility stream leak" unless positive["post_stream"]["stream"] == (100..124).to_a
raise "metadata SQL absent" unless sql.any? { |query| query.include?("FROM discourse_reactions_reactions") }
raise "secret cooked leak" if JSON.generate(positive).include?("secret")

near_tables = JSON.parse(JSON.generate(tables))
near_tables["discourse_reactions_reactions"].reject! { |row| row["post_id"] == 124 }
near, = topic_fixture(conn, near_tables, 200, 25)
raise "near window metadata copied from first post" unless near["post_stream"]["posts"].all? { |post| post["reaction_users_count"] == 0 && post["reactions"] == [] }

disabled = JSON.parse(JSON.generate(tables))
disabled["site_settings"].find { |row| row["name"] == "discourse_reactions_enabled" }["value"] = "f"
body, queries = topic_fixture(conn, disabled)
raise "disabled topic plugin field" if body.key?("valid_reactions") || body["post_stream"]["posts"].any? { |post| post.keys.any? { |key| %w[reactions reaction_users_count current_user_reaction current_user_used_main_reaction].include?(key) } }
raise "disabled plugin ran reactor SQL" if queries.any? { |query| query.include?("discourse_reactions_reactions") || query.include?("discourse_reactions_reaction_users") || query.include?("FROM post_actions") }

missing, queries = topic_fixture(conn, tables, 999)
raise "missing topic must be absent" unless missing.nil?
raise "missing topic queried reactors" if queries.any? { |query| query.include?("discourse_reactions_reactions") || query.include?("discourse_reactions_reaction_users") }
restricted = JSON.parse(JSON.generate(tables))
restricted["categories"][0]["read_restricted"] = true
body, queries = topic_fixture(conn, restricted)
raise "restricted topic must be absent" unless body.nil?
raise "restricted topic queried reactors" if queries.any? { |query| query.include?("discourse_reactions_reactions") || query.include?("discourse_reactions_reaction_users") }

File.write("build/reaction-topic-native.json", JSON.generate({ "synthetic" => true, "read_only" => true,
  "positive_metadata" => positive["post_stream"]["posts"][0].slice("reactions", "reaction_users_count", "current_user_reaction", "current_user_used_main_reaction"),
  "selected_post_ids" => positive["post_stream"]["posts"].map { |post| post["id"] },
  "positive_sql" => sql, "disabled_no_fields_or_reactor_sql" => true,
  "missing_restricted_no_reactor_sql" => true, "deleted_whisper_nonselected_not_queried" => true,
  "near_window_empty_metadata" => true }))
conn.close
puts "PASS full native topic reactions path: positive/disabled/missing/restricted/selected-window visibility (synthetic read-only CTEs)"
