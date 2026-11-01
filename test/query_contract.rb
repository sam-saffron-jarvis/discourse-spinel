# SELECT-only fixtures shadow source tables with typed CTE records. No temporary
# tables, DDL, inserts, updates, rollback writes, or shared data changes.
require "pg"
require "json"
require_relative "../lib/latest"

raise "explicit task DB required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
raise "explicit task Valkey URL required" unless ENV.fetch("REDIS_URL") == "redis://127.0.0.1:6399/0"
conn = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")

FIXTURE_QUERY = NativeLatest::QUERY.sub("WITH eligible", <<~SQL.strip)
  WITH topics AS (SELECT * FROM json_populate_recordset(NULL::public.topics, $5::json)),
  categories AS (SELECT * FROM json_populate_recordset(NULL::public.categories, $6::json)),
  eligible
SQL

def topic(id, day)
  { "id" => id, "title" => "fixture #{id}", "fancy_title" => "fixture #{id}",
    "archetype" => "regular", "visible" => true, "category_id" => -100,
    "pinned_globally" => false, "created_at" => "2026-01-01T00:00:00Z",
    "bumped_at" => "2026-02-#{day.to_s.rjust(2, '0')}T00:00:00Z" }
end

def ids_for(conn, topics, categories, page = 0, definitions = false, drafts = "", muted = "{}")
  result = conn.exec_params(FIXTURE_QUERY, [page.to_s, definitions ? "true" : "false", drafts, muted, JSON.generate(topics), JSON.generate(categories)])
  ids = []
  result.ntuples.times { |i| ids << JSON.parse(result.getvalue(i, 0).to_s)["id"].to_i }
  ids
end

def check(actual, expected, label)
  raise "#{label}: #{actual.inspect} != #{expected.inspect}" unless actual == expected
  puts label
end

categories = [
  { "id" => -100, "read_restricted" => false, "topic_id" => -1006 },
  { "id" => -101, "read_restricted" => true },
  { "id" => -102, "read_restricted" => false },
]
fixtures = [
  topic(-1001, 20),
  topic(-1002, 22).merge("visible" => false),
  topic(-1003, 23).merge("archetype" => "private_message"),
  topic(-1004, 24).merge("deleted_at" => "2026-02-25T00:00:00Z"),
  topic(-1005, 25).merge("category_id" => -101),
  topic(-1006, 26),
  topic(-1007, 1).merge("pinned_globally" => true, "pinned_at" => "2026-02-01T00:00:00Z"),
  topic(-1008, 18).merge("pinned_at" => "2026-02-02T00:00:00Z"),
  topic(-1009, 19).merge("category_id" => -102),
]
check(ids_for(conn, fixtures, categories), [-1007, -1001, -1009, -1008], "visibility: public/deleted/unlisted/PM/private/category-definition; global pin first")
check(ids_for(conn, fixtures, categories, 0, true), [-1007, -1006, -1001, -1009, -1008], "category definitions setting")
check(ids_for(conn, fixtures, categories, 0, false, "-102"), [-1007, -1001, -1008], "shared drafts category excluded")
check(ids_for(conn, fixtures, categories, 0, false, "", "{-102}"), [-1007, -1001, -1008], "anonymous default-muted category excluded")
changed = fixtures.map { |t| t["id"] == -1008 ? t.merge("bumped_at" => "2026-03-01T00:00:00Z", "title" => "changed live data") : t }
check(ids_for(conn, changed, categories), [-1007, -1008, -1001, -1009], "changed source data changes order; local pin not globally prioritized")
categoryless = [topic(-1010, 17).merge("category_id" => nil)]
check(ids_for(conn, categoryless, categories), [-1010], "categoryless topic allowed with default settings")
check(ids_for(conn, categoryless, categories, 0, false, "-102"), [], "shared-draft SQL preserves NULL category exclusion")
check(ids_for(conn, categoryless, categories, 0, false, "", "{-102}"), [], "muted-category SQL preserves NULL category exclusion")

many = []
35.times do |i|
  many << topic(-2000 - i, 1).merge("bumped_at" => "2026-03-01T00:00:#{(59 - i).to_s.rjust(2, '0')}Z")
end
many << topic(-3000, 1).merge("pinned_globally" => true, "pinned_at" => "2026-02-02T00:00:00Z")
many << topic(-3001, 1).merge("pinned_globally" => true, "pinned_at" => "2026-02-01T00:00:00Z")
first = [-3000, -3001] + 28.times.map { |i| -2000 - i }
second = 7.times.map { |i| -2028 - i }
check(ids_for(conn, many, categories), first, "30-row first page includes two global pins in pinned_at order")
check(ids_for(conn, many, categories, 1), second, "second page compensates pinned offset without repeats")
check(ids_for(conn, many, categories, 2), [], "exhausted page")
conn.close
