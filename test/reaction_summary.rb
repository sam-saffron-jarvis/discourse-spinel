# frozen_string_literal: true
# Read-only typed CTE parity fixtures for the distinct post reactions summary action.
require "pg"
require "json"
require "time"
require_relative "../lib/reaction_summary"

raise "task PG required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET TIME ZONE 'UTC'")
conn.exec("SET statement_timeout = '5s'")

def check(value, label)
  raise label unless value
  puts label
end

# The fixture adapter injects typed CTE table shadows before the unchanged SQL.
REACTION_SUMMARY_CTE = <<~SQL.freeze
  WITH users AS (SELECT * FROM json_populate_recordset(NULL::public.users, '__USERS__'::json)),
    discourse_reactions_reactions AS (SELECT * FROM json_populate_recordset(NULL::public.discourse_reactions_reactions, '__REACTIONS__'::json)),
    discourse_reactions_reaction_users AS (SELECT * FROM json_populate_recordset(NULL::public.discourse_reactions_reaction_users, '__REACTION_USERS__'::json)),
    post_actions AS (SELECT * FROM json_populate_recordset(NULL::public.post_actions, '__POST_ACTIONS__'::json)),
SQL

now = Time.now.to_i.to_f
stamp = ->(seconds_ago) { Time.at(now - seconds_ago).utc.iso8601(6) }
users = [{ "id" => -1, "username" => "system", "name" => "System", "uploaded_avatar_id" => nil }]
(1..90).each do |id|
  users << { "id" => id, "username" => "user#{id}", "name" => (id.even? ? "Name #{id}" : nil), "uploaded_avatar_id" => (id == 2 ? 52 : nil) }
end
reactions = [
  { "id" => 10, "post_id" => 100, "reaction_value" => "heart", "reaction_users_count" => 30 },
  { "id" => 11, "post_id" => 100, "reaction_value" => "clap", "reaction_users_count" => 3 },
  { "id" => 12, "post_id" => 100, "reaction_value" => "disabled", "reaction_users_count" => nil },
  { "id" => 13, "post_id" => 100, "reaction_value" => "laughing", "reaction_users_count" => 0 },
  { "id" => 14, "post_id" => 100, "reaction_value" => "hugs", "reaction_users_count" => 1 },
  { "id" => 15, "post_id" => 100, "reaction_value" => "other", "reaction_users_count" => 1 },
  { "id" => 17, "post_id" => 100, "reaction_value" => nil, "reaction_users_count" => 1 },
  { "id" => 16, "post_id" => 101, "reaction_value" => "heart", "reaction_users_count" => 2 },
  { "id" => 18, "post_id" => 102, "reaction_value" => "heart", "reaction_users_count" => nil },
  { "id" => 20, "post_id" => 100, "reaction_value" => "heartwithdash", "reaction_users_count" => 2 },
  { "id" => 21, "post_id" => 104, "reaction_value" => "heart", "reaction_users_count" => nil },
  { "id" => 22, "post_id" => 105, "reaction_value" => "heart", "reaction_users_count" => 1 },
]
reaction_users = 30.times.map do |i|
  { "id" => 1000 + i, "post_id" => 100, "user_id" => 31 + i, "reaction_id" => 10, "created_at" => stamp.call(1800 + i * 30) }
end
reaction_users.concat([
  { "id" => 2001, "post_id" => 100, "user_id" => 2, "reaction_id" => 11, "created_at" => stamp.call(120) },
  { "id" => 2002, "post_id" => 100, "user_id" => 3, "reaction_id" => 11, "created_at" => stamp.call(1500) },
  { "id" => 2008, "post_id" => 100, "user_id" => 12, "reaction_id" => 11, "created_at" => stamp.call(600) },
  { "id" => 2003, "post_id" => 100, "user_id" => 5, "reaction_id" => 12, "created_at" => stamp.call(1600) },
  { "id" => 2004, "post_id" => 100, "user_id" => 6, "reaction_id" => 13, "created_at" => stamp.call(1700) },
  { "id" => 2005, "post_id" => 100, "user_id" => 7, "reaction_id" => 14, "created_at" => stamp.call(30) },
  { "id" => 2006, "post_id" => 100, "user_id" => 8, "reaction_id" => 15, "created_at" => stamp.call(60) },
  { "id" => 2007, "post_id" => 100, "user_id" => 9, "reaction_id" => 17, "created_at" => stamp.call(45) },
  { "id" => 2010, "post_id" => 101, "user_id" => 10, "reaction_id" => 16, "created_at" => stamp.call(60) },
  { "id" => 2011, "post_id" => 102, "user_id" => 11, "reaction_id" => 18, "created_at" => stamp.call(60) },
  { "id" => 2012, "post_id" => 100, "user_id" => 13, "reaction_id" => 20, "created_at" => stamp.call(120) },
  { "id" => 2022, "post_id" => 105, "user_id" => 50, "reaction_id" => 22, "created_at" => stamp.call(1.8) },
])
post_actions = 80.times.map do |i|
  { "id" => 3000 + i, "post_id" => 100, "user_id" => i + 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(i + 1) }
end
# A reaction actor's shadow-like, disabled historical like, deleted like, and
# non-like action must not be mistaken for independent main-reaction likes.
post_actions.concat(30.times.map { |i| { "id" => 4000 + i, "post_id" => 103, "user_id" => i + 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(i + 1) } } +
  30.times.map { |i| { "id" => 5000 + i, "post_id" => 104, "user_id" => i + 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(i + 1) } } + [
  { "id" => 3100, "post_id" => 100, "user_id" => 5, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(31) },
  { "id" => 3101, "post_id" => 100, "user_id" => 70, "post_action_type_id" => 2, "deleted_at" => stamp.call(2), "created_at" => stamp.call(2) },
  { "id" => 3102, "post_id" => 100, "user_id" => 1, "post_action_type_id" => 1, "deleted_at" => nil, "created_at" => stamp.call(3) },
  { "id" => 3103, "post_id" => 100, "user_id" => -1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(4) },
  { "id" => 6000, "post_id" => 105, "user_id" => 1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(1.2) },
  { "id" => 6100, "post_id" => 106, "user_id" => -1, "post_action_type_id" => 2, "deleted_at" => nil, "created_at" => stamp.call(10) },
])

cte_json = {
  "__USERS__" => JSON.generate(users),
  "__REACTIONS__" => JSON.generate(reactions),
  "__REACTION_USERS__" => JSON.generate(reaction_users),
  "__POST_ACTIONS__" => JSON.generate(post_actions),
}
cte = REACTION_SUMMARY_CTE.gsub(/'__(?:USERS|REACTIONS|REACTION_USERS|POST_ACTIONS)__'/) do |token|
  "'#{cte_json.fetch(token.delete("'")).gsub("'", "''")}'"
end

class ReactionSummaryFixtureConnection
  def initialize(connection, prefix)
    @connection, @prefix = connection, prefix
  end
  def exec_params(sql, binds = [])
    if sql.lstrip.start_with?("WITH ")
      sql = sql.sub(/\AWITH\s+/, @prefix)
    elsif sql.lstrip.start_with?("SELECT")
      sql = @prefix.sub(/,\s*\z/, " ") + sql
    end
    @connection.exec_params(sql, binds)
  end
  def exec(sql) = @connection.exec(sql)
end

fixture_conn = ReactionSummaryFixtureConnection.new(conn, cte)
class SummaryFixtureSettings
  def initialize(enabled_reactions: "+1|laughing|open_mouth|clap|confetti_ball|hugs", main: "heart", names: true, undo: 10, logo_small: "-6")
    @values = { "discourse_reactions_enabled_reactions" => enabled_reactions,
      "discourse_reactions_reaction_for_like" => main, "post_undo_action_window_mins" => undo,
      "enable_names" => names, "use_site_small_logo_as_system_avatar" => true, "logo_small" => logo_small }
  end
  def enabled?(name, fallback) = @values.fetch(name, fallback)
  def value(name, fallback) = @values.fetch(name, fallback)
end
settings = SummaryFixtureSettings.new

# Filter, post, names visibility, human-readable assertion.
specs = [
  [nil, 100, true, "all reaction summaries include enabled reaction rows and the merged main likes"],
  ["heart", 100, true, "main filter merges plain likes with historical main reaction users"],
  ["clap", 100, true, "specific filter returns matching reaction only and never merges likes"],
  ["", 100, true, "explicit blank string is a specific source reaction filter"],
  ["   ", 100, true, "whitespace string is a specific source reaction filter"],
  ["disabled", 100, true, "disabled historical reaction with NULL counter is excluded"],
  ["laughing", 100, true, "zero counter remains a source-present row"],
  ["missing", 100, true, "unknown specific reaction returns an empty summary"],
  [nil, 101, true, "historical main reaction is omitted when there are no plain likes"],
  [nil, 102, true, "main reaction with NULL counter and no likes is omitted"],
  ["clap", 100, false, "names-disabled reaction users omit name"],
  [nil, 103, true, "likes without any main-reaction definition still produce capped main summary"],
  [nil, 104, true, "likes with NULL-counter main definition still produce capped main summary"],
  [nil, 105, true, "subsecond ties serialize to source seconds without an added tie-breaker"],
  ["heartwithdash", 100, true, "changed enabled reactions and hyphenated main setting normalize source main reaction", { main: "heart-with-dash", enabled_reactions: "+1|clap" }],
  [nil, 106, true, "system user's summary avatar uses actual instance system-logo shortcut"],
  ["heart", 100, true, "non-main reaction users preserve descending source order and truncate to27", { main: "clap" }],
  [nil, 100, false, "names-disabled summary omits names from likes and all reaction groups"],
]
cases = specs.map do |filter, post_id, names_enabled, label, overrides|
  overrides ||= {}
  case_settings = SummaryFixtureSettings.new(names: names_enabled, **overrides)
  result = NativeReactionSummary.summary(fixture_conn, post_id, filter, case_settings, now)
  [filter, post_id, names_enabled, label, result, overrides]
end

check(cases[17][4]["reaction_users"].all? { |group| group["users"].all? { |user| !user.key?("name") } }, specs[17][3])
cap = cases[16][4].fetch("reaction_users").first
check(cap["count"] == 30 && cap["users"].length == 27 && cap["users"].map { |u| u["username"] } == (31..57).map { |i| "user#{i}" }, specs[16][3])
all = cases[0][4].fetch("reaction_users")
main = cases[1][4].fetch("reaction_users")
check(all.map { |r| r["id"] }.include?("heart") && all.none? { |r| r["id"] == "disabled" }, specs[0][3])
check(main.length == 1 && main[0]["id"] == "heart", specs[1][3])
check(cases[2][4]["reaction_users"].map { |r| r["id"] } == ["clap"], specs[2][3])
check(cases[3][4]["reaction_users"].empty? && cases[4][4]["reaction_users"].empty?, "explicit blank and whitespace filters are specific values, not absent filter")
check(cases[5][4]["reaction_users"].empty?, specs[5][3])
check(cases[6][4]["reaction_users"].length == 1 && cases[6][4]["reaction_users"][0]["count"] == 0, "zero reaction counter remains a source-present row with zero count")
check(cases[7][4]["reaction_users"].empty?, specs[7][3])
check(cases[8][4]["reaction_users"].empty? && cases[9][4]["reaction_users"].empty?, "no-likes historical main with positive or NULL counter is omitted")
no_main_summary = cases[11][4]["reaction_users"]
check(no_main_summary.length == 1 && no_main_summary[0]["id"] == "heart" && no_main_summary[0]["count"] == 30 && no_main_summary[0]["users"].length == 27 && no_main_summary[0]["users"].map { |u| u["username"] } == (1..27).to_a.reverse.map { |i| "user#{i}" }, specs[11][3])
null_counter_likes = cases[12][4]["reaction_users"]
check(null_counter_likes.length == 1 && null_counter_likes[0]["count"] == 30 && null_counter_likes[0]["users"].length == 27 && null_counter_likes[0]["users"].map { |u| u["username"] } == (1..27).to_a.reverse.map { |i| "user#{i}" }, specs[12][3])
tied_users = cases[13][4]["reaction_users"][0]["users"]
check(tied_users.length == 2 && tied_users[0]["created_at"] == tied_users[1]["created_at"], specs[13][3])
changed_main = cases[14][4]["reaction_users"]
check(changed_main.length == 1 && changed_main[0]["id"] == "heartwithdash" && changed_main[0]["count"] >= 2, specs[14][3])
heart = all.find { |r| r["id"] == "heart" }
check(heart["count"] > heart["users"].length, "main reaction count reflects all source likes/counter, not truncated users")
check(heart["users"].length == 27, "main reaction truncates to source MAX_USERS_COUNT plus one")
check(heart["users"].all? { |u| Time.parse(u["created_at"]).to_f > now - 1800 }, "plain likes cap before merge and reverse, so the capped recent likes displace older main reaction users")
check(heart["users"].each_cons(2).all? { |a, b| a["created_at"] >= b["created_at"] }, "merged main users sort newest-first before truncation")
check(all.find { |r| r["id"] == "clap" }["users"].each_cons(2).all? { |a, b| a["created_at"] >= b["created_at"] }, "reaction users order by source created_at descending")
check(all.flat_map { |r| r["users"] }.count { |u| u["username"] == "user9" } == 2, "NULL-valued reaction stays visible and can duplicate the same actor's source like")
check(all.flat_map { |r| r["users"] }.count { |u| u["username"] == "user2" } == 1, "valid reaction actor shadow-like is excluded from merged summaries")
check(all.map { |r| r["id"] }.include?("other") && heart["users"].none? { |u| u["username"] == "user8" }, "disabled non-NULL historical reaction remains visible but suppresses its shadow-like")
check(heart["users"].none? { |u| u["username"] == "user5" }, "disabled historical reaction user does not reappear as a shadow-like")
check(all.flat_map { |r| r["users"] }.any? { |u| u["can_undo"] } && all.flat_map { |r| r["users"] }.any? { |u| !u["can_undo"] }, "reaction can_undo uses explicit 10-minute source window")
clap_users = all.find { |r| r["id"] == "clap" }["users"]
check(clap_users.find { |u| u["username"] == "user2" }["can_undo"] && !clap_users.find { |u| u["username"] == "user12" }["can_undo"] && !clap_users.find { |u| u["username"] == "user3" }["can_undo"], "can_undo strict boundary rejects exactly 10 minutes and older")
check(cases[10][4]["reaction_users"][0]["users"].all? { |u| !u.key?("name") }, specs[10][3])
check(cases[15][4]["reaction_users"][0]["users"][0]["avatar_template"] == "/images/discourse-logo-sketch-small.png", specs[15][3])
system_row = { "id" => -1, "username" => "system", "name" => "System", "uploaded_avatar_id" => nil, "created_at" => stamp.call(4), "can_undo" => false }
custom_logo_rejected = begin
  NativeReactionSummary.serialize_summary_user(system_row, SummaryFixtureSettings.new(logo_small: "custom-logo"))
  false
rescue RuntimeError => error
  error.message == "unsupported reaction summary system logo"
end
check(custom_logo_rejected, "custom system-logo override is rejected rather than fabricated")
array_values = ["a\\b", "a\"b", "a,b", "{x}"]
array_result = conn.exec_params("SELECT unnest($1::text[])", [NativeReactionSummary.pg_array(array_values)])
check(array_result.ntuples == array_values.length && array_result.ntuples.times.map { |i| array_result.getvalue(i, 0).to_s } == array_values, "PostgreSQL array binding round-trips backslashes quotes commas and braces")
check(all.any? { |r| r["id"].nil? }, "all-reactions Ruby comparison includes a non-null-count row with NULL reaction_value")

valid_request = NativeReactionSummaryRequest.new("/discourse-reactions/posts/100/reactions-users.json", "reaction_value=heart")
absent_filter_request = NativeReactionSummaryRequest.new("/discourse-reactions/posts/100/reactions-users.json", "")
check(valid_request.id == 100 && valid_request.reaction_filter == "heart" && absent_filter_request.reaction_filter.nil?, "summary request accepts only optional scalar reaction_value and preserves absent versus blank")
bad_requests = [
  ["/discourse-reactions/posts/-1/reactions-users.json", ""],
  ["/discourse-reactions/posts/100/reactions-users.json", "reaction_value=a&reaction_value=b"],
  ["/discourse-reactions/posts/100/reactions-users.json", "unknown=1"],
  ["/discourse-reactions/posts/100/reactions-users.json", "reaction_value[]=heart"],
]
bad_count = bad_requests.count do |path, query|
  begin
    NativeReactionSummaryRequest.new(path, query)
    false
  rescue ArgumentError
    true
  end
end
check(bad_count == bad_requests.length, "malformed summary paths duplicate and unsupported query parameters fail closed")

# Reuse010's exact native POST_QUERY as a read-only visibility negative fixture.
visibility_data = {
  "posts" => [{ "id" => 900, "topic_id" => 910, "post_type" => 1, "hidden" => false },
    { "id" => 901, "topic_id" => 911, "post_type" => 1, "hidden" => true },
    { "id" => 902, "topic_id" => 912, "post_type" => 1, "hidden" => false },
    { "id" => 903, "topic_id" => 910, "post_type" => 1, "hidden" => false, "deleted_at" => stamp.call(20) },
    { "id" => 904, "topic_id" => 913, "post_type" => 1, "hidden" => false },
    { "id" => 905, "topic_id" => 914, "post_type" => 1, "hidden" => false },
    { "id" => 906, "topic_id" => 910, "post_type" => 4, "hidden" => false }],
  "topics" => [{ "id" => 910, "archetype" => "regular", "category_id" => 920 },
    { "id" => 911, "archetype" => "regular", "category_id" => 920 },
    { "id" => 912, "archetype" => "private_message", "category_id" => 920 },
    { "id" => 913, "archetype" => "regular", "category_id" => 920, "deleted_at" => stamp.call(20) },
    { "id" => 914, "archetype" => "regular", "category_id" => 921 }],
  "categories" => [{ "id" => 920, "read_restricted" => false }, { "id" => 921, "read_restricted" => true }],
  "shared_drafts" => [],
}
visibility_cte = "WITH " + visibility_data.map do |table, rows|
  json = JSON.generate(rows).gsub("'", "''")
  "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table},'#{json}'::json))"
end.join(", ") + " "
visibility_sql = visibility_cte + NativeReactions::POST_QUERY
public_post = conn.exec_params(visibility_sql, ["900", "false"])
hidden_post = conn.exec_params(visibility_sql, ["901", "false"])
hidden_allowed = conn.exec_params(visibility_sql, ["901", "true"])
private_post = conn.exec_params(visibility_sql, ["902", "true"])
check(public_post.ntuples == 1 && public_post.getvalue(0, 1) == "t" && hidden_post.getvalue(0, 1) == "f" && private_post.getvalue(0, 1) == "f", "native POST_QUERY denies hidden and private posts while allowing public post")
check(hidden_allowed.getvalue(0, 1) == "t", "native POST_QUERY grants hidden visibility only via explicit group-visibility setting")

class SummaryGuardRows
  def initialize(rows) = @rows = rows
  def ntuples = @rows.length
  def getvalue(row, col) = @rows[row][col]
end
class DisabledSummaryConnection
  attr_reader :commands
  def initialize(settings = [["discourse_reactions_enabled", "f"]])
    @commands, @settings = [], settings
  end
  def exec(sql)
    @commands << sql
    SummaryGuardRows.new([])
  end
  def exec_params(sql, _binds)
    @commands << sql
    SummaryGuardRows.new(@settings)
  end
end
disabled_conn = DisabledSummaryConnection.new
disabled_status, = NativeReactionSummary.new(disabled_conn).call(absent_filter_request)
check(disabled_status == 404 && disabled_conn.commands.any? { |sql| sql.start_with?("ROLLBACK") } && disabled_conn.commands.none? { |sql| sql.include?("FROM posts") }, "disabled plugin guard exits before post/reaction queries and rolls back read-only transaction")
login_conn = DisabledSummaryConnection.new([["login_required", "t"]])
login_status, = NativeReactionSummary.new(login_conn).call(absent_filter_request)
check(login_status == 403 && login_conn.commands.last == "ROLLBACK" && login_conn.commands.length == 3, "login-required summary fails closed before content queries and rolls back")

# Run the actual summary call through its real PG visibility query, refusing
# any reactor query on denied data. Settings dependency is in-memory only.
class DeniedSummaryConnection
  attr_reader :commands
  def initialize(conn, prefix)
    @conn, @prefix, @commands = conn, prefix, []
  end
  def exec(sql)
    @commands << sql
    @conn.exec(sql)
  end
  def exec_params(sql, binds)
    @commands << sql
    if sql.start_with?("SELECT name, value FROM site_settings")
      SummaryGuardRows.new([])
    elsif sql == NativeReactions::POST_QUERY
      @conn.exec_params(@prefix + sql, binds)
    else
      raise "denied post reached reaction summary SQL"
    end
  end
end
visibility_cases = [900,901,902,903,904,905,906,999].map do |id|
  row = conn.exec_params(visibility_sql, [id.to_s, "false"])
  found = row.ntuples > 0
  allowed = found && row.getvalue(0, 1) == "t"
  status = NativeReactions.access_status(SummaryFixtureSettings.new, found, allowed)
  unless allowed
    guard = DeniedSummaryConnection.new(conn, visibility_cte)
    actual, = NativeReactionSummary.new(guard).call(NativeReactionSummaryRequest.new("/discourse-reactions/posts/#{id}/reactions-users.json", ""))
    raise "summary visibility status mismatch" unless actual == status && guard.commands.last == "ROLLBACK"
  end
  { "id" => id, "status" => status }
end
check(visibility_cases.map { |row| row["status"] } == [200,403,403,404,403,403,403,404], "summary call denies hidden private deleted missing restricted and whisper fixtures before any reactor query")

report_cases = cases.map do |filter, post_id, names_enabled, label, result, overrides|
  overrides ||= {}
  { "filter" => filter, "post_id" => post_id,
    "main" => overrides.fetch(:main, "heart"),
    "enabled_reactions" => overrides.fetch(:enabled_reactions, settings.value("discourse_reactions_enabled_reactions", "")),
    "names_enabled" => names_enabled, "undo_minutes" => 10, "now" => now,
    "reaction_users" => result.fetch("reaction_users"), "label" => label }
end
File.write("build/reaction-summary-fixtures-native.json", JSON.generate({
  "synthetic" => true, "read_only" => true,
  "tables" => { "users" => users, "discourse_reactions_reactions" => reactions,
    "discourse_reactions_reaction_users" => reaction_users, "post_actions" => post_actions },
  "cases" => report_cases,
  "visibility" => { "tables" => visibility_data, "cases" => visibility_cases },
}))
check(File.file?("build/reaction-summary-fixtures-native.json"), "synthetic native reaction-summary fixture report written under build")
conn.close
