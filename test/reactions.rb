# Read-only typed CTE fixtures for native reactions SQL and access policy.
require "pg"
require "json"
require_relative "../lib/reactions"
raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")

def check(value, label)
  raise label unless value
  puts label
end

# Each query shadows every production table it reads; no site records are touched.
REACTION_FIXTURE = <<~SQL
  WITH users AS (SELECT * FROM json_populate_recordset(NULL::public.users,$1::json)),
    discourse_reactions_reactions AS (SELECT * FROM json_populate_recordset(NULL::public.discourse_reactions_reactions,$2::json)),
    discourse_reactions_reaction_users AS (SELECT * FROM json_populate_recordset(NULL::public.discourse_reactions_reaction_users,$3::json)),
    post_actions AS (SELECT * FROM json_populate_recordset(NULL::public.post_actions,$4::json)),
SQL
POST_FIXTURE = <<~SQL
  WITH posts AS (SELECT * FROM json_populate_recordset(NULL::public.posts,$1::json)),
    topics AS (SELECT * FROM json_populate_recordset(NULL::public.topics,$2::json)),
    categories AS (SELECT * FROM json_populate_recordset(NULL::public.categories,$3::json)),
    shared_drafts AS (SELECT * FROM json_populate_recordset(NULL::public.shared_drafts,$4::json))
SQL

users = [
  { "id" => 1, "username" => "system", "name" => "System", "uploaded_avatar_id" => nil },
  { "id" => 2, "username" => "alice", "name" => "Alice Example", "uploaded_avatar_id" => 55 },
  { "id" => 3, "username" => "bob", "name" => nil, "uploaded_avatar_id" => nil },
  { "id" => 4, "username" => "carol", "name" => "Carol", "uploaded_avatar_id" => nil },
]
reactions = [
  { "id" => 10, "reaction_value" => "heart", "reaction_users_count" => 1 },
  { "id" => 11, "reaction_value" => "smile", "reaction_users_count" => 1 },
  { "id" => 12, "reaction_value" => "disabled", "reaction_users_count" => nil },
]
reaction_users = [
  { "post_id" => 100, "user_id" => 2, "reaction_id" => 10, "created_at" => "2025-01-01T00:00:02Z" },
  { "post_id" => 100, "user_id" => 3, "reaction_id" => 11, "created_at" => "2025-01-01T00:00:04Z" },
  # Historical and nil-counter reactions still suppress an otherwise plain like.
  { "post_id" => 100, "user_id" => 4, "reaction_id" => 12, "created_at" => "2025-01-01T00:00:06Z" },
  { "post_id" => 101, "user_id" => 2, "reaction_id" => 11, "created_at" => "2025-01-01T00:00:01Z" },
  # Missing profile user contributes to unfiltered source total but not returned rows.
  { "post_id" => 100, "user_id" => 999, "reaction_id" => 11, "created_at" => "2025-01-01T00:00:08Z" },
]
post_actions = [
  { "post_id" => 100, "user_id" => 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:01Z" },
  { "post_id" => 100, "user_id" => 2, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:03Z" },
  { "post_id" => 100, "user_id" => 3, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:05Z" },
  { "post_id" => 100, "user_id" => 4, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:07Z" },
  { "post_id" => 100, "user_id" => 1, "post_action_type_id" => 2, "deleted_at" => "2025-01-02T00:00:00Z", "created_at" => "2025-01-01T00:00:09Z" },
  { "post_id" => 100, "user_id" => 1, "post_action_type_id" => 1, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:10Z" },
  { "post_id" => 101, "user_id" => 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => "2025-01-01T00:00:00Z" },
]

native_query = lambda do |sql, binds|
  shifted = sql.gsub(/\$(\d+)/) { "$#{Regexp.last_match(1).to_i + 4}" }
  fixture = REACTION_FIXTURE + shifted.sub(/\AWITH /, "")
  conn.exec_params(fixture, [JSON.generate(users), JSON.generate(reactions), JSON.generate(reaction_users), JSON.generate(post_actions), *binds])
end
run_case = lambda do |filter, main, limit = 30, offset = 0|
  binds = ["100", main, filter, limit.to_s, offset.to_s]
  rows = native_query.call(NativeReactions.rows_sql(filter, main), binds)
  parsed = rows.ntuples.times.map { |i| JSON.parse(rows.getvalue(i, 0).to_s) }
  total = native_query.call(NativeReactions.total_sql(filter, main), binds).getvalue(0, 0).to_s.to_i
  [parsed, total]
end

all_rows, all_total = run_case.call("", "heart")
check(all_rows.map { |r| r["id"].to_i } == [1, 2, 3, 4] && all_total == 5, "all reactions merge ASC and count source reaction rows without user join")
check(all_rows.map { |r| r["reaction"] } == ["heart", "heart", "smile", "disabled"], "plain likes map to configured main reaction and nil-count historical values remain rows")
check(run_case.call("heart", "heart").then { |rows, total| rows.map { |r| r["id"].to_i } == [1] && total == 1 }, "main filter returns plain likes and excludes historical reaction users")
check(run_case.call("smile", "heart").then { |rows, total| rows.map { |r| r["id"].to_i } == [3] && total == 2 }, "specific filter joins reaction definitions and omits missing profiles only from rows")
check(run_case.call(" ", "heart").then { |rows, total| rows.length == 4 && total == 5 }, "whitespace filter follows source blank semantics")
check(run_case.call("unknown", "heart").then { |rows, total| rows.empty? && total == 0 }, "unknown filter is a specific reaction filter")
page_rows, page_total = run_case.call("", "heart", 1, 1)
check(page_rows.map { |r| r["id"].to_i } == [2] && page_total == all_total, "offset pagination preserves stable unpaged total")
check(run_case.call("", "heart", 1, 0)[0].length == 1 && run_case.call("", "heart", 1, 2)[0].length == 1, "ascending timestamp pagination yields adjacent rows")
check(run_case.call("", "heart-with-dash")[0].any? { |r| r["reaction"] == "heart-with-dash" }, "main reaction mapping is supplied by caller and tags plain likes")

class ReactionTestSettings
  def initialize(values = {}) = @values = values
  def enabled?(name, fallback) = @values.fetch(name, fallback)
  def value(name, fallback) = @values.fetch(name, fallback)
end
names_off = ReactionTestSettings.new("enable_names" => false)
names_on = ReactionTestSettings.new
private_user = NativeReactions.serialize_user({ "id" => 2, "username" => "alice", "name" => "Alice Example", "uploaded_avatar_id" => 55, "reaction" => "heart" }, names_off)
check(!private_user.key?("name") && private_user["avatar_template"].end_with?("/55_2.png"), "reaction serializer omits names and retains uploaded avatar source")
nil_user = NativeReactions.serialize_user({ "id" => 3, "username" => "bob", "name" => nil, "uploaded_avatar_id" => nil, "reaction" => "smile" }, names_on)
check(nil_user.key?("name") && nil_user["name"].nil? && nil_user["avatar_template"].include?("{size}"), "enabled names retains nullable name and default letter avatar")
system_user = NativeReactions.serialize_user({ "id" => -1, "username" => "system", "name" => "System", "uploaded_avatar_id" => nil, "reaction" => "heart" }, names_on)
check(system_user["avatar_template"] != "/images/discourse-logo-sketch-small.png" && system_user["avatar_template"].start_with?("/letter_avatar_proxy/"), "reaction serializer uses User.avatar_template source semantics rather than instance system logo")

class FakeRows
  def initialize(rows) = @rows = rows
  def ntuples = @rows.length
  def getvalue(row, col) = @rows[row][col]
end
class SettingsFakeConnection
  def initialize(values) = @values = values
  def exec_params(sql, params)
    raise "unexpected settings query" unless sql.start_with?("SELECT name, value FROM site_settings") && params.length == 1
    FakeRows.new(@values.map { |pair| pair })
  end
end
settings = NativeReactionsSettings.new(SettingsFakeConnection.new([["granular_anonymous_and_logged_in_groups_permissions", "t"], ["hidden_post_visible_groups", "14|4"]]))
check(settings.hidden_visible?, "hidden visibility requires granular permissions and explicit group 4")
main_setting = NativeReactionsSettings.new(SettingsFakeConnection.new([["discourse_reactions_reaction_for_like", "heart-with-dash"]]))
check(main_setting.value("discourse_reactions_reaction_for_like", "heart").gsub("-", "") == "heartwithdash", "configured main reaction removes hyphens as source mapping")
check(!NativeReactionsSettings.new(SettingsFakeConnection.new([["hidden_post_visible_groups", "4"]])).hidden_visible?, "hidden group setting alone does not enable granular visibility")
access_results = [ReactionTestSettings.new("login_required" => true), ReactionTestSettings.new("discourse_reactions_enabled" => false), names_on, names_on, names_on].each_with_index.map { |setting, i| NativeReactions.access_status(setting, [true,true,false,true,true][i], [true,true,true,false,true][i]) }
check(access_results == [403,404,404,403,200], "access status gives login/plugin/not-found/inaccessible source precedence")

# PostgreSQL typed fixture matches Post.find's undeleted scope and the source Guardian policy.
post_values = [
  { "id" => 100, "topic_id" => 200, "post_type" => 1, "hidden" => false },
  { "id" => 101, "topic_id" => 200, "post_type" => 1, "hidden" => true },
  { "id" => 102, "topic_id" => 201, "post_type" => 1, "deleted_at" => "2025-01-01" },
  { "id" => 103, "topic_id" => 200, "post_type" => 4 },
  { "id" => 104, "topic_id" => 202, "post_type" => 1 },
  { "id" => 105, "topic_id" => 203, "post_type" => 1 },
  { "id" => 106, "topic_id" => 204, "post_type" => 1 },
  { "id" => 107, "topic_id" => 999, "post_type" => 1 },
  { "id" => 109, "topic_id" => 205, "post_type" => 1 },
  { "id" => 108, "topic_id" => 206, "post_type" => 1 },
]
topic_values = [
  { "id" => 200, "archetype" => "regular", "category_id" => 300, "visible" => false },
  { "id" => 201, "archetype" => "regular", "category_id" => 300 },
  { "id" => 202, "archetype" => "private_message", "category_id" => 300 },
  { "id" => 203, "archetype" => "regular", "category_id" => 300, "deleted_at" => "2025-01-01" },
  { "id" => 204, "archetype" => "regular", "category_id" => nil },
  { "id" => 205, "archetype" => "regular", "category_id" => 300 },
  { "id" => 206, "archetype" => "regular", "category_id" => 301 },
]
category_values = [{ "id" => 300, "read_restricted" => false }, { "id" => 301, "read_restricted" => true }]
draft_values = [{ "topic_id" => 205 }]
post_sql = NativeReactions::POST_QUERY.gsub(/\$(\d+)/) { "$#{Regexp.last_match(1).to_i + 4}" }
post_fixture_sql = POST_FIXTURE + post_sql.sub(/\AWITH /, "")
post_fixture_params = [JSON.generate(post_values), JSON.generate(topic_values), JSON.generate(category_values), JSON.generate(draft_values)]
visibility = [100, 101].to_h do |id|
  row = conn.exec_params(post_fixture_sql, [*post_fixture_params, id.to_s, "false"])
  [id, row.ntuples == 1 && row.getvalue(0, 1) == "t"]
end
check(visibility == { 100 => true, 101 => false }, "post query allows public direct and unlisted access but rejects hidden by default")
[102, 103, 104, 105, 106, 107, 108].each do |id|
  found = conn.exec_params(post_fixture_sql, [*post_fixture_params, id.to_s, "true"])
  check(found.ntuples == 0 || found.getvalue(0, 1) == "f", "post lookup denies deleted/whisper/PM/deleted-topic/missing-or-restricted-category/draft/foreign fixtures #{id}")
end
missing_post = conn.exec_params(post_fixture_sql, [*post_fixture_params, "999", "true"])
deleted_post = conn.exec_params(post_fixture_sql, [*post_fixture_params, "102", "true"])
check(missing_post.ntuples == 0 && deleted_post.ntuples == 0, "missing and deleted posts follow Post.find undeleted lookup")
draft_post = conn.exec_params(post_fixture_sql, [*post_fixture_params, "109", "false"])
check(draft_post.ntuples == 1 && draft_post.getvalue(0, 1) == "f", "post query excludes actual synthetic shared draft dependency")
hidden_group = conn.exec_params(post_fixture_sql, [*post_fixture_params, "101", "true"])
check(hidden_group.ntuples == 1 && hidden_group.getvalue(0, 1) == "t", "hidden post admitted only through group-visibility bind")

# Exercise the real call's early disabled-plugin guard without any production query or write.
class CallFakeConnection
  attr_reader :calls
  def initialize(settings_rows) = (@settings_rows = settings_rows; @calls = [])
  def exec(sql)
    @calls << sql
    raise "unexpected transaction command" unless sql.include?("READ ONLY") || sql == "ROLLBACK"
    FakeRows.new([])
  end
  def exec_params(sql, params)
    @calls << sql
    if sql.start_with?("SELECT name, value FROM site_settings")
      FakeRows.new(@settings_rows)
    else
      raise "disabled plugin reached content query"
    end
  end
end
fake_call_conn = CallFakeConnection.new([["discourse_reactions_enabled", "f"]])
call_status, call_body = NativeReactions.new(fake_call_conn).call(NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list", ""))
check(call_status == 404 && JSON.parse(call_body)["error"].include?("disabled") && fake_call_conn.calls.length == 3, "real call exits disabled before post or reaction queries and rolls back read-only transaction")

request = NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list.json", "page=-3xyz&limit=500tail&reaction_value=heart")
check(request.id == 100 && request.page == 0 && request.limit == 50 && request.reaction_filter == "heart", "request uses scalar to_i prefix parsing and source clamps")
check(NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list", "page=2.7&limit=words").then { |r| r.page == 2 && r.limit == 1 }, "numeric prefixes and junk values preserve String to_i behavior before clamping")
check(NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list", "page=1_02tail&limit=%C2%A0").then { |r| r.page == 102 && r.limit == 1 }, "underscored integers and nonblank Unicode limit follow source fast_blank coercions")
check(!NativeReactionsRequest.blank?("\u00a0") && run_case.call("\u00a0", "heart")[1] == 0, "Unicode space is a specific filter under actual source fast_blank predicate")
bad_queries = ["x[]=1", "page=1&page=2", "admin=true", "limit=#{'8' * 257}", "%ZZ=1", "limit=2147483648", "page=-2147483649", "reaction_value=%00", "reaction_value=%FF"]
rejected = bad_queries.count do |query|
  begin
    NativeReactionsRequest.new("/discourse-reactions/posts/100/reactions-users-list", query)
    false
  rescue ArgumentError
    true
  end
end
check(rejected == bad_queries.length, "arrays duplicates unknown huge malformed and out-of-range parameters fail closed")
rejected_routes = ["/discourse-reactions/posts/-1/reactions-users-list", "/discourse-reactions/posts/2147483648/reactions-users-list", "/discourse-reactions/posts/1/reactions-users-list/extra"].count do |path|
  begin
    NativeReactionsRequest.new(path, "")
    false
  rescue ArgumentError
    true
  end
end
check(rejected_routes == 3, "malformed routes and unsupported numeric ID ranges fail closed")

# The verifier can compare the native result independently against the same synthetic CTE data.
report_cases = [["", "heart", 30, 0, true], ["heart", "heart", 30, 0, true], ["smile", "heart", 30, 0, true], [" ", "heart", 30, 0, true], ["unknown", "heart", 30, 0, true], ["", "heart", 1, 1, true], ["", "heart", 30, 0, false], ["\u00a0", "heart", 30, 0, true]].map do |filter, main, limit, offset, names_enabled|
  rows, total = run_case.call(filter, main, limit, offset)
  canonical_rows = rows.map { |row| row.reject { |key, _| key == "created_at" } }
  serialized = rows.map { |row| NativeReactions.serialize_user(row, ReactionTestSettings.new("enable_names" => names_enabled)) }
  { filter: filter, main: main, limit: limit, offset: offset, post_id: 100, rows: canonical_rows, total: total, names_enabled: names_enabled, users: serialized }
end
visibility_cases = [100,101,102,103,104,105,106,107,108,109,999].map do |id|
  result = conn.exec_params(post_fixture_sql, [*post_fixture_params, id.to_s, "false"])
  { id: id, found: result.ntuples > 0, allowed: result.ntuples > 0 && result.getvalue(0, 1) == "t" }
end
File.write("build/reactions-fixtures-native.json", JSON.generate({ synthetic: true, tables: { users: users, discourse_reactions_reactions: reactions, discourse_reactions_reaction_users: reaction_users, post_actions: post_actions }, cases: report_cases,
  visibility: { tables: { posts: post_values, topics: topic_values, categories: category_values, shared_drafts: draft_values }, cases: visibility_cases } }))
check(File.file?("build/reactions-fixtures-native.json"), "synthetic native parity fixture report written under build")
conn.close
