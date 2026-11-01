# Compiled native integration, SELECT-only own taskPG5499. Never a request server.
require "pg"
require "json"
require_relative "../vendor/rack-mini-profiler/spinel_mini_profiler"
require_relative "../lib/latest"
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
raw.close
