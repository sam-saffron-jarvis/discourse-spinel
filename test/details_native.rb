# frozen_string_literal: true
# Compiled Spinel test of the real NativeTopic path over typed SELECT-only CTEs.
# Fixture rows are synthetic inputs; expected cooked output comes only from the
# source-fixtures.json PrettyText.cook oracle, never hand-authored snapshots.
require "pg"
require "json"
require_relative "../lib/topic"
require_relative "../reference/native_site"

EXPECTED_DATABASE_URL = "postgres://discourse@127.0.0.1:5499/discourse_development"
raise "task PG identity mismatch" unless ENV.fetch("DATABASE_URL") == EXPECTED_DATABASE_URL
raise "PG must be configured read-only" unless ENV.fetch("PGOPTIONS", "").include?("default_transaction_read_only=on")

source = JSON.parse(File.read("build/details/source-fixtures.json"))
raise "source fixture must be read-only actual cooker output" unless source["read_only"] && source["source"] == "actual PrettyText.cook"
source_cases = source.fetch("cases")
raise "combined reader fixture missing" unless source_cases.any? { |item| item["name"] == "reader_combined" }

fixture_id = 910016
posts = source_cases.each_with_index.map do |item, index|
  { "id" => fixture_id + index, "topic_id" => fixture_id, "post_number" => index + 1,
    "sort_order" => index + 1, "post_type" => 1, "user_id" => 1,
    "hidden" => false, "cooked" => item.fetch("cooked") }
end

tables = {
  "topics" => [{ "id" => fixture_id, "title" => "Details cooked fixture", "fancy_title" => "Details cooked fixture",
    "slug" => "details-cooked-fixture", "posts_count" => posts.length, "created_at" => "2025-01-01T00:00:00Z",
    "last_posted_at" => "2025-01-01T00:00:00Z", "visible" => true, "closed" => false, "archived" => false,
    "has_summary" => false, "archetype" => "regular", "category_id" => 1, "word_count" => 0,
    "user_id" => 1, "last_post_user_id" => 1, "pinned_globally" => false }],
  "categories" => [{ "id" => 1, "read_restricted" => false }],
  "posts" => posts,
  "users" => [{ "id" => 1, "username" => "details_fixture", "name" => "Details Fixture",
    "admin" => false, "moderator" => false, "trust_level" => 1 }],
  "groups" => [], "topic_tags" => [], "shared_drafts" => [], "uploads" => [],
  "site_settings" => [{ "name" => "details_enabled", "value" => "t" },
    { "name" => "discourse_reactions_enabled", "value" => "f" }]
}

class DetailsFixtureCTEConnection
  attr_reader :queries, :executions

  def initialize(connection, tables)
    @connection = connection
    @queries = []
    @executions = []
    @cte = "WITH " + tables.map do |name, rows|
      encoded = JSON.generate(rows).gsub("'", "''")
      "#{name} AS (SELECT * FROM json_populate_recordset(NULL::public.#{name},'#{encoded}'::json))"
    end.join(", ") + " "
  end

  def exec(sql)
    @queries << sql
    if sql.lstrip.start_with?("SELECT")
      @executions << { "sql" => @cte + sql, "binds" => [] }
      @connection.exec(@cte + sql)
    else
      @connection.exec(sql)
    end
  end

  def exec_params(sql, binds)
    @queries << sql
    if sql.lstrip.start_with?("SELECT")
      @executions << { "sql" => @cte + sql, "binds" => binds }
      @connection.exec_params(@cte + sql, binds)
    else
      @connection.exec_params(sql, binds)
    end
  end
end

connection = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
connection.exec("SET default_transaction_read_only = on")
connection.exec("SET statement_timeout = '5s'")
identity_result = connection.exec("SELECT current_database(), current_user, inet_server_addr()::text, inet_server_port(), current_setting('default_transaction_read_only')")
identity = { "current_database" => identity_result.getvalue(0, 0), "current_user" => identity_result.getvalue(0, 1),
  "inet_server_addr" => identity_result.getvalue(0, 2), "inet_server_port" => identity_result.getvalue(0, 3),
  "current_setting" => identity_result.getvalue(0, 4) }
raise "native task PG identity/read-only mismatch: #{identity.inspect}" unless identity["current_database"] == "discourse_development" && identity["current_user"] == "discourse" && identity["inet_server_addr"].to_s.split("/").first == "127.0.0.1" && identity["inet_server_port"].to_i == 5499 && identity["current_setting"] == "on"

setting_values = {}
{ "missing" => [], "enabled" => [{ "name" => "details_enabled", "value" => "t" }],
  "disabled" => [{ "name" => "details_enabled", "value" => "f" }] }.each do |label, setting_rows|
  settings_adapter = DetailsFixtureCTEConnection.new(connection, { "site_settings" => setting_rows, "uploads" => [] })
  settings = NativeReference.read_client_settings(settings_adapter)
  setting_values[label] = settings.fetch("details_enabled")
  expected = label == "disabled" ? false : true
  raise "NativeReference details_enabled #{label} projection mismatch" unless setting_values[label] == expected
  raise "client settings CTE used non-SELECT query" unless settings_adapter.queries.all? { |sql| sql.lstrip.start_with?("SELECT") }
end
raise "native client setting default differs from source YAML" unless setting_values.fetch("missing") == source.dig("source_setting", "default")

def details_topic_response(connection, base_tables, setting_value, topic_id)
  tables = JSON.parse(JSON.generate(base_tables))
  tables["site_settings"].reject! { |row| row["name"] == "details_enabled" }
  tables["site_settings"] << { "name" => "details_enabled", "value" => setting_value ? "t" : "f" }
  adapter = DetailsFixtureCTEConnection.new(connection, tables)
  [JSON.parse(NativeTopic.new(adapter, {}).call(topic_id, 1)), adapter.queries, adapter.executions]
end

response, native_queries, native_executions = details_topic_response(connection, tables, true, fixture_id)
returned_posts = response.fetch("post_stream").fetch("posts")
raise "compiled NativeTopic omitted fixture posts" unless returned_posts.length == source_cases.length
actual_by_id = {}
returned_posts.each { |post| actual_by_id[post.fetch("id")] = post.fetch("cooked") }
cases = source_cases.each_with_index.map do |item, index|
  id = fixture_id + index
  cooked = actual_by_id.fetch(id)
  raise "native cooked changed source #{item.fetch('name')}" unless cooked == item.fetch("cooked")
  { "name" => item.fetch("name"), "post_id" => id, "cooked" => cooked,
    "source_cooked_match" => true }
end
combined = cases.find { |item| item["name"] == "reader_combined" }
raise "compiled combined case differs from actual source cooker" unless combined.fetch("cooked") == source_cases.find { |item| item["name"] == "reader_combined" }.fetch("cooked")

responses_by_setting = { "enabled" => response }
responses_by_setting["disabled"], disabled_queries, disabled_executions = details_topic_response(connection, tables, false, fixture_id)
["enabled", "disabled"].each do |label|
  actual_cooked = responses_by_setting.fetch(label).fetch("post_stream").fetch("posts").map { |post| post.fetch("cooked") }
  raise "NativeTopic cooked changed when details_enabled=#{label}" unless actual_cooked == source_cases.map { |item| item.fetch("cooked") }
end
all_queries = native_queries + disabled_queries
raise "CTE fixture queries were not SELECT-only" unless all_queries.all? { |sql| sql.lstrip.start_with?("SELECT") || sql.lstrip.start_with?("BEGIN") || sql.strip == "ROLLBACK" }

artifact = { "read_only" => true, "synthetic" => true,
  "fixture_contract" => "NativeTopic.call actual compiled response over typed json_populate_recordset CTEs",
  "task_pg_identity" => identity, "client_setting_values" => setting_values,
  "topic_id" => fixture_id, "topic_response" => response,
  "topic_cooked_by_setting" => { "enabled" => responses_by_setting["enabled"].fetch("post_stream").fetch("posts").map { |post| post.fetch("cooked") },
    "disabled" => responses_by_setting["disabled"].fetch("post_stream").fetch("posts").map { |post| post.fetch("cooked") } },
  "cases" => cases, "combined_case" => combined, "browser_cooked" => combined.fetch("cooked"),
  "select_only_queries" => all_queries, "actual_typed_cte_executions" => native_executions + disabled_executions }
File.write("build/details/native-fixtures.json", JSON.generate(artifact))
connection.close
puts "PASS compiled NativeTopic preserves all #{cases.length} source-cooked cases with details setting on/off; NativeReference client setting values pass"
