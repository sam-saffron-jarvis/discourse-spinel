# frozen_string_literal: true
# Observe normal guarded Rails boot; never seed, alter storage or wrap methods.
require "json"
package = File.expand_path("../../run/bundle/ruby/4.0.0/gems/discourse-seed-fu-2.3.12", __dir__)
base = File.expand_path("../../discourse", __dir__)
events = []
vips_retitle_control = []
trace = TracePoint.new(:line, :call, :return, :b_call) do |event|
  if ENV["FIDELITY_TEST_VIPS_RETITLE"] == "1" && event.event == :return && event.method_id == :start && event.defined_class&.name == "DiscourseVips::WorkerProcess"
    pid = event.self.pid
    sleep 1
    command = File.binread("/proc/#{pid}/cmdline").split("\0")
    raise "retitle control did not reach the original worker title" unless command == ["discourse vips worker"]
    vips_retitle_control << { pid: pid, command_after_original_start: command }
  end
  package_body = event.path.start_with?(package + "/") && [:line, :b_call].include?(event.event)
  accessor = [:fixture_paths, :fixture_paths=].include?(event.method_id) && event.self.is_a?(Module) && event.self.name == "SeedFu"
  producer = event.event == :call && event.method_id == :register_seedfu_fixtures && event.defined_class&.name == "Plugin::Instance"
  next unless package_body || accessor || producer
  raise "unbounded SeedFu trace" if events.length >= 200
  row = { order: events.length + 1, event: event.event, method: event.method_id,
          source: [event.path, event.lineno], thread: Thread.current.object_id, receiver_class: event.self.class.name,
          receiver_module: event.self.is_a?(Module) ? event.self.name : nil }
  if producer || (accessor && event.event == :call)
    row[:plugin_source] = event.self.instance_variable_get(:@path) if producer
    row[:original_callers] = caller_locations.filter_map do |location|
      [location.path, location.lineno] if location.path.start_with?(base + "/")
    end
  end
  if accessor && event.event == :return && event.return_value.is_a?(Array)
    row[:observed_paths] = event.return_value.map(&:to_s)
  end
  events << row
end
trace.enable
begin
  load File.join(__dir__, "oracle.rb")
ensure
  trace.disable
  puts "FIDELITY_SEEDFU_TRACE " + JSON.generate({ scope: "original SeedFu declarations/initializer/storage observations ONLY; no native state or seed execution", successful_oracle: $!.nil?, events: events, vips_retitle_control: vips_retitle_control,
    loaded_seedfu_sources: $LOADED_FEATURES.select { |path| path.start_with?(package + "/") && path.end_with?(".rb") }.sort })
end
