# Compiled native integration, SELECT-only own taskPG5499. Never a request server.
require "pg"
require "json"
require_relative "../vendor/rack-mini-profiler/spinel_mini_profiler"
require_relative "../lib/latest"
require_relative "../lib/mini_profiler"
raise "explicit task DB required" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
raise "explicit task Valkey required" unless ENV.fetch("REDIS_URL") == "redis://127.0.0.1:6399/0"

def check(condition, label)
  raise label unless condition
  puts label
end

raw = PG.connect("127.0.0.1", 5499, "discourse_development", "discourse", "")
raw.exec("SET default_transaction_read_only = on")
raw.exec("SET statement_timeout = '5s'")
raw.exec("SET TIME ZONE 'UTC'")
connection = SpinelMiniProfilerConnection.new(raw)
profiler = SpinelMiniProfiler.new
request = profiler.start("/latest", "GET")
connection.request = request
begin
  connection.exec("SELECT pg_sleep(0.02)")
  result = connection.exec_params("SELECT $1::text", ["private-password-bind"])
  check(result.getvalue(0, 0).to_s == "private-password-bind", "real exec_params preserves result")
  result = connection.exec("SELECT 'private-password-literal'::text")
  check(result.getvalue(0, 0).to_s == "private-password-literal", "real exec preserves result")
  begin
    connection.exec("SELECT 1 / 0")
    raise "expected database error"
  rescue PG::Error => error
    check(error.message.include?("division by zero"), "real failed PG call preserves original exception")
  end
ensure
  connection.request = nil
end
id = profiler.save(request)
json = profiler.result(id).to_s
profile = JSON.parse(json)
timings = profile["root"]["sql_timings"]
check(profile["sql_count"] == 4 && profile["custom_fields"]["Failed PG calls"] == "1", "real successful and failed exec calls recorded")
check(timings[0]["duration_milliseconds"] >= 18 && timings[0]["duration_milliseconds"] < 1000, "pg_sleep 20ms measured as actual latency")
check(profile["duration_milliseconds"] >= profile["duration_milliseconds_in_sql"] && timings[3]["failed"] == true, "real request and SQL elapsed plus failed annotation")
check(!json.include?("private-password") && !json.include?("division by zero") && timings[1]["formatted_command_string"].include?("$1"), "real SQL secrets redacted while placeholders retained")
File.write("build/profiler-pg.json", json)

# Same actual latest extraction, with and without collection, in this process.
emoji = JSON.parse(File.read("data/emoji-unicode.json"))
latest = NativeLatest.new(connection, emoji)
plain = latest.call(0)
fresh = profiler.start("/latest.json", "GET")
connection.request = fresh
begin
  measured = latest.call(0)
ensure
  connection.request = nil
end
fresh_id = profiler.save(fresh)
fresh_profile = JSON.parse(profiler.result(fresh_id).to_s)
check(JSON.parse(plain) == JSON.parse(measured), "real latest JSON identical with profiler enabled and disabled")
check(fresh_profile["sql_count"] > 1 && fresh_profile["custom_fields"]["Failed PG calls"] == "0" && !profiler.result(fresh_id).to_s.include?("pg_sleep"), "new latest request has no previous queries or failed state")
File.write("build/profiler-latest-native.json", profiler.result(fresh_id).to_s)
# Combined integration: actual topic extraction uses the same request-local PG
# decorator without changing its JSON or retaining previous request SQL.
adapter = NativeMiniProfiler.new("")
parsed = JSON.parse(plain)
topic_id = parsed["topic_list"]["topics"][0]["id"].to_i
topics = NativeTopic.new(connection, emoji)
plain_topic = topics.call(topic_id)
topic_request = adapter.start("/t/private-title/#{topic_id}.json", "GET")
connection.request = topic_request
begin
  measured_topic = topics.call(topic_id)
ensure
  connection.request = nil
end
profile = JSON.parse(topic_request.finish)
check(plain_topic == measured_topic, "real topic JSON bytes identical with profiler enabled and disabled")
check(profile["request_path"] == "/t/#{topic_id}.json" && profile["root"]["name"] == "GET /t/#{topic_id}.json", "topic profiler names use numeric route identity without user slugs")
check(profile["sql_count"] > 1 && profile["root"]["sql_timings"].any? { |timing| timing["formatted_command_string"].include?("FROM posts") } && !topic_request.finish.include?("pg_sleep"), "topic profiler records actual topic and post SQL without previous request state")
check(adapter.start("/t/caf%C3%A9/#{topic_id}/2.json", "GET").finish.include?("/t/#{topic_id}/2.json"), "escaped topic slugs profile through safe canonical numeric near-post names")
check(adapter.start("/t/0.json", "GET").nil? && adapter.start("/t/x/1/0.json", "GET").nil? && adapter.start("/t/1.json", "POST").nil?, "malformed topic routes and mutation requests are not profiled")
File.write("build/profiler-topic-native.json", topic_request.finish)
raw.close
