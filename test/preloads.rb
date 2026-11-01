# SELECT-only typed CTE fixtures: no shared rows, temporary tables, DDL or writes.
require "pg"
require "json"
require_relative "../lib/preloads"
raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")

QUERY = <<~SQL + NativePreloads::BANNER_QUERY
  WITH topics AS (SELECT * FROM json_populate_recordset(NULL::public.topics, $1::json)),
       categories AS (SELECT * FROM json_populate_recordset(NULL::public.categories, $2::json)),
       posts AS (SELECT * FROM json_populate_recordset(NULL::public.posts, $3::json))
SQL

def banner(conn, topics, categories, posts)
  result = conn.exec_params(QUERY, [JSON.generate(topics), JSON.generate(categories), JSON.generate(posts)])
  result.ntuples == 0 ? {} : JSON.parse(result.getvalue(0, 0).to_s)
end

def check(value, label)
  raise label unless value
  puts label
end

topics = [
  { "id" => 1, "slug" => "restricted", "archetype" => "banner", "category_id" => 2 },
  { "id" => 2, "slug" => "deleted", "archetype" => "banner", "category_id" => 1, "deleted_at" => "2026-01-01" },
  { "id" => 3, "slug" => "public", "archetype" => "banner", "category_id" => 1 },
]
categories = [{ "id" => 1, "read_restricted" => false }, { "id" => 2, "read_restricted" => true }]
posts = [
  { "topic_id" => 1, "post_number" => 1, "cooked" => "restricted body" },
  { "topic_id" => 2, "post_number" => 1, "cooked" => "deleted topic body" },
  { "topic_id" => 3, "post_number" => 1, "cooked" => "deleted post body", "deleted_at" => "2026-01-01" },
  { "topic_id" => 3, "post_number" => 3, "cooked" => "later public body" },
  { "topic_id" => 3, "post_number" => 2, "cooked" => "first live body" },
]
value = banner(conn, topics, categories, posts)
check(value == { "key" => 3, "url" => "/t/public/3", "html" => "first live body" }, "banner excludes restricted deleted topics and deleted posts using source post order")
posts[4]["cooked"] = "changed live body"
check(banner(conn, topics, categories, posts)["html"] == "changed live body", "banner responds to changed source rows without captured HTML")
check(banner(conn, topics[0, 2], categories, posts).empty?, "banner returns empty only when no eligible source topic exists")
conn.close
