# frozen_string_literal: true
# Original no-plugin Rails reference. Query observations are not replacement
# native application code or captured inputs for a compiler.
raise "unexpected plugin profile" unless ENV["LOAD_PLUGINS"] == "0" && !GlobalSetting.load_plugins?
raise "plugin instances present" unless Discourse.plugins.empty?
require_relative "query_initializer_oracle_consumer"
raise "original list_latest owner changed" unless TopicQuery.instance_method(:list_latest).source_location == [File.expand_path("lib/topic_query.rb"), 305]
calls = []
seen = {}
settings = []
root = File.expand_path(".") + "/"
trace = TracePoint.new(:call, :b_call) do |event|
  next unless event.path.start_with?(root)
  key = [event.path.delete_prefix(root), event.lineno, event.method_id, event.defined_class.to_s]
  unless seen[key]
    seen[key] = true
    calls << {source: key[0], line: key[1], method: key[2], owner: key[3]}
  end
  if event.self.equal?(SiteSetting) && event.event == :call
    settings << {method: event.method_id, source: key[0], line: event.lineno}
  end
end
sql = FidelityDriver.capture do
  trace.enable
  @core_reference_list = TopicQuery.new(nil, per_page: 20).list_latest
ensure
  trace.disable
end
list = @core_reference_list
raise "not the original TopicList" unless list.is_a?(TopicList)
rows = list.topics.map { |topic| {id: topic.id, slug: topic.slug, title: topic.title, category_id: topic.category_id} }
raise "core query returned no live topics" if rows.empty?
puts "FIDELITY_CORE_REFERENCE " + JSON.generate({
  scope: "actual original anonymous list_latest with no plugins; NOT native parity or page completion",
  query_owner: TopicQuery.instance_method(:list_latest).source_location,
  list_owner: TopicList.instance_method(:initialize).source_location,
  rows: rows, row_count: rows.length, sql: sql, original_core_calls: calls, actual_setting_calls: settings,
  first_core_reader: {name: :nested_replies_enabled,
    source: SiteSetting.method(:nested_replies_enabled).source_location,
    arity: SiteSetting.method(:nested_replies_enabled).arity,
    parameters: SiteSetting.method(:nested_replies_enabled).parameters},
})

if ENV["FIDELITY_CORE_HTTP_REFERENCE"] == "1"
  require "rack/mock"
  requests = {}
  ["/latest.json", "/latest"].each do |path|
    response = nil
    url = URI.parse(Discourse.base_url + path)
    request_host = url.host + (url.default_port == url.port ? "" : ":#{url.port}")
    request_calls = []
    request_seen = {}
    request_trace = TracePoint.new(:call, :b_call) do |event|
      next unless event.path.start_with?(root)
      key = [event.path.delete_prefix(root), event.lineno, event.method_id, event.defined_class.to_s]
      unless request_seen[key]
        request_seen[key] = true
        request_calls << {source: key[0], line: key[1], method: key[2], owner: key[3]}
      end
    end
    request_sql = FidelityDriver.capture do
      request_trace.enable
      response = Rack::MockRequest.new(Rails.application).get(
        url.to_s,
        "HTTP_HOST" => request_host,
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_ACCEPT" => (path.end_with?(".json") ? "application/json" : "text/html"),
      )
    ensure
      request_trace.disable
    end
    output = File.join(ENV.fetch("FIDELITY_CORE_REFERENCE_DIRECTORY"), path.delete_prefix("/") + ".response")
    File.binwrite(output, response.body)
    requests[path] = {
      request_url: url.to_s, request_host: request_host, anonymous: true,
      status: response.status, content_type: response["content-type"],
      location: response["location"], body_sha256: Digest::SHA256.hexdigest(response.body),
      body_bytes: response.body.bytesize, sql: request_sql, original_core_calls: request_calls,
    }
    if path.end_with?(".json") && response.status == 200
      parsed = JSON.parse(response.body)
      requests[path][:top_level_keys] = parsed.keys
      requests[path][:topic_ids] = parsed.fetch("topic_list").fetch("topics").map { |topic| topic.fetch("id") }
      requests[path][:topic_keys] = parsed.fetch("topic_list").fetch("topics").first&.keys
    end
  end
  puts "FIDELITY_CORE_HTTP_REFERENCE " + JSON.generate({
    profile: "original-core-no-plugins", requests: requests,
    native_equal: false, core_page_accepted: false,
  })
end
