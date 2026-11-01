# SELECT-only typed CTE topic/post visibility, ordering and window fixtures.
require "pg"
require "json"
require_relative "../lib/topic"
raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")

def check(value, label)
  raise label unless value
  puts label
end

TOPIC_FIXTURE = <<~SQL + NativeTopic::TOPIC_QUERY
  WITH topics AS (SELECT * FROM json_populate_recordset(NULL::public.topics,$2::json)),
    categories AS (SELECT * FROM json_populate_recordset(NULL::public.categories,$3::json)),
    shared_drafts AS (SELECT * FROM json_populate_recordset(NULL::public.shared_drafts,$4::json))
SQL
POST_FIXTURE = <<~SQL + NativeTopic::POSTS_QUERY
  WITH posts AS (SELECT * FROM json_populate_recordset(NULL::public.posts,$3::json))
SQL

def eligible(conn, topic, categories, drafts = [])
  conn.exec_params(TOPIC_FIXTURE, [topic["id"].to_s, JSON.generate([topic]), JSON.generate(categories), JSON.generate(drafts)]).ntuples == 1
end

def posts(conn, values)
  rows = conn.exec_params(POST_FIXTURE, ["100", NativeTopic::HIDDEN_COOKED, JSON.generate(values)])
  result = []
  rows.ntuples.times { |i| result << JSON.parse(rows.getvalue(i, 0).to_s) }
  result
end

topic = { "id" => 100, "archetype" => "regular", "visible" => true, "category_id" => 1 }
categories = [{ "id" => 1, "read_restricted" => false }, { "id" => 2, "read_restricted" => true }]
check(eligible(conn, topic, categories), "topic permits source public direct access")
check(eligible(conn, topic.merge("visible" => false), categories), "topic direct unlisted link follows Guardian rather than latest visibility")
check(!eligible(conn, topic.merge("deleted_at" => "2026-01-01"), categories), "topic excludes deleted topics")
check(!eligible(conn, topic.merge("archetype" => "private_message"), categories), "topic excludes private messages")
check(!eligible(conn, topic.merge("category_id" => 2), categories), "topic excludes restricted categories")
check(!eligible(conn, topic.merge("category_id" => nil), categories) && !eligible(conn, topic.merge("category_id" => 999), categories), "topic Guardian denies absent and nonexistent categories unlike list SQL")
check(!eligible(conn, topic, categories, [{ "topic_id" => 100 }]), "topic excludes shared drafts even in public categories")
values = [
  { "id" => 10, "topic_id" => 100, "post_number" => 1, "sort_order" => 5, "post_type" => 1, "cooked" => "first live", "reads" => 0, "hidden" => false },
  { "id" => 11, "topic_id" => 100, "post_number" => 2, "sort_order" => 8, "post_type" => 1, "cooked" => "deleted secret", "deleted_at" => "2026-01-01" },
  { "id" => 12, "topic_id" => 100, "post_number" => 3, "sort_order" => 2, "post_type" => 4, "cooked" => "whisper secret" },
  { "id" => 13, "topic_id" => 100, "post_number" => 4, "sort_order" => 3, "post_type" => 1, "hidden" => true, "cooked" => "hidden secret" },
  { "id" => 14, "topic_id" => 100, "post_number" => 5, "sort_order" => 4, "post_type" => 2, "hidden" => false, "cooked" => "moderator action" },
  { "id" => 15, "topic_id" => 101, "post_number" => 1, "sort_order" => 1, "post_type" => 1, "cooked" => "other topic secret" },
  { "id" => 16, "topic_id" => 100, "post_number" => 6, "sort_order" => 6, "post_type" => 3, "hidden" => false, "cooked" => "small action" },
]
result = posts(conn, values)
check(result.map { |p| p["id"] } == [13,14,10,16], "post stream excludes deleted whisper foreign posts and uses sort_order not IDs/numbers")
check(result[0]["cooked"] == NativeTopic::HIDDEN_COOKED && !JSON.generate(result).include?("secret"), "hidden cooked redacted at SQL boundary and raw never selected")
check(result[2]["readers_count"] == 0 && result[2]["score"] == 0.0, "source readers count and nil score getters")
values[0]["cooked"] = "changed live cooked"
check(posts(conn, values)[2]["cooked"] == "changed live cooked", "topic reads changed cooked source rows without fixtures")
many = 40.times.map { |i| { "id" => i + 1, "sort_order" => i + 1 } }
check(NativeTopic.window(many, 20).map { |p| p["id"] } == (15..34).to_a, "near-post source window loads five before and fifteen from target")
check(NativeTopic.window(many, 40).map { |p| p["id"] } == (21..40).to_a, "near-post source window backfills from earlier visible posts at end")
check(NativeTopic.window(many, 1).map { |p| p["id"] } == (1..20).to_a, "near-post first window never underflows")
request = NativeTopicRequest.new("/t/source-title/123/7.json", "track_visit=true&forceLoad=true")
check(request.id == 123 && request.post_number == 7 && request.json, "slug route and source client transport flags")
request = NativeTopicRequest.new("/t/123/7.json", "")
check(request.id == 123 && request.post_number == 7, "numeric source topic and post-number route")
bad = 0
["/t/0.json", "/t/-1.json", "/t/x/1/0.json", "/t/x/2147483648.json", "/t/x/1/2/3.json", "/t/x%2fy/1.json"].each do |path|
  begin
    NativeTopicRequest.new(path, "")
  rescue ArgumentError
    bad += 1
  end
end
check(bad == 6, "malformed topic IDs routes post-numbers and encoded separators fail closed")
bad = 0
["post_ids[]=12", "show_deleted=true", "filter=summary", "username_filters[]=staff", "track_visit=1", "track_visit=true&track_visit=false", "raw=true", "post_number=2"].each do |query|
  begin
    NativeTopicRequest.new("/t/1.json", query)
  rescue ArgumentError
    bad += 1
  end
end
check(bad == 8, "unsupported filters raw deleted and duplicate parameters never widen visibility")
class TopicTestSettings
  def enabled?(name, fallback)
    fallback
  end
  def value(name, fallback)
    fallback
  end
end
system = { "id" => -1, "username" => "system", "name" => "system", "primary_group_id" => nil }
serialized = NativeTopic.new(conn, {}).serialize_post({ "user_id" => -1 }, { "posts_count" => 1, "slug" => "source" }, { -1 => system }, { 0 => { "name" => "everyone" } }, TopicTestSettings.new)
check(serialized["primary_group_name"].nil?, "missing primary group never aliases actual group zero everyone")
serializer = NativeTopic.new(conn, {})
null_score = serializer.serialize_post({ "score_is_null" => true }, {}, {}, {}, TopicTestSettings.new)
zero_score = serializer.serialize_post({ "score_is_null" => false, "score" => 0 }, {}, {}, {}, TopicTestSettings.new)
check(null_score["score"].is_a?(Integer) && zero_score["score"].is_a?(Float), "post score preserves source nil fallback integer versus stored float zero")
conn.close
