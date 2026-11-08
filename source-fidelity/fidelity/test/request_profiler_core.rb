# frozen_string_literal: true
# UNIT-only direct caller of actual source-derived profiler5 records and store.
require_relative "../compat/framework/rack_mini_profiler_core"
env = {"SERVER_NAME" => "localhost", "SERVER_PORT" => "3000", "SCRIPT_NAME" => "", "REQUEST_METHOD" => "GET", "PATH_INFO" => "/latest.json", "QUERY_STRING" => "page=1"}
Rack::MiniProfiler.create_current(env)
page = Rack::MiniProfiler.current.page_struct
Thread.current[:unrelated_unit_symbol_hash] = {marker: true}
Rack::MiniProfiler.add_snapshot_custom_field("Application version", "unit-source-version")
Rack::MiniProfiler.add_snapshot_custom_field("Second field", "unit-second-value")
raise "snapshot fields changed or collided with timer hashes" unless Rack::MiniProfiler.get_snapshot_custom_fields == {"Application version" => "unit-source-version", "Second field" => "unit-second-value"}
page[:root].add_sql("SELECT '<actual&query>'", 1.0, page, nil, false, false, false)
child = page[:root].add_child("Executing actual controller action")
child.record_time(0.25)
page[:root].record_time(1.25)
page[:user] = Digest::MD5.hexdigest("127.0.0.1")
payload = Marshal.dump(page)
restored = Marshal.load(payload)
raise "wrong profiler ID" unless restored[:id] == page[:id]
raise "wrong timer values" unless restored[:root][:duration_milliseconds] == 1.25
raise "wrong root page backreference" unless restored[:root].instance_variable_get(:@page).equal?(restored)
json = JSON.parse(restored.to_json)
raise "wrong request" unless json["request_path"] == "/latest.json" && json["request_method"] == "GET"
raise "wrong aggregate duration" unless json["duration_milliseconds"] == 1.25
raise "SQL counter was fabricated/lost" unless json["sql_count"] == 1
raise "real SQL field escaping changed" unless json["root"]["sql_timings"][0]["formatted_command_string"] == "SELECT &#39;&lt;actual&amp;query&gt;&#39;"
Rack::MiniProfiler.current = nil
raise "profiler context leak" unless Rack::MiniProfiler.current.nil?
raise "snapshot fields leaked context cleanup" unless Rack::MiniProfiler.get_snapshot_custom_fields.nil?
begin
  Rack::MiniProfiler::Context.new({"measure" => false})
  raise "unsupported context options accepted"
rescue ArgumentError
end
puts "PASS actual profiler5 Page/SQL/child timers, cyclic Marshal storage, JSON fields and context cleanup"
