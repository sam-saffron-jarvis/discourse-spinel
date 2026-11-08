# frozen_string_literal: true
# TEST-only genuine Rails route/middleware/controller request observations.
# Never loaded by a native executable or used as its runtime data source.
if ENV["FIDELITY_JSON_REQUEST_BASE_CONSUMER"] == "settings"
  require_relative "portable_rails_reference_consumer"
else
  require_relative "serialized_latest_reference_consumer"
end
require "rack/mock"
require_relative "latest_profiler_reference_probe"

paths = [
  "/latest.json",
  "/latest.json?per_page=2&page=0",
  "/latest.json?per_page=2&page=1",
  "/latest.json?per_page=2&page=2",
  "/latest.json?per_page=3&order=created&ascending=true",
  "/latest.json?page=not-an-integer",
]
observations = []
paths.each_with_index do |path, index|
  url = URI.parse(Discourse.base_url + path)
  host = url.host + (url.default_port == url.port ? "" : ":#{url.port}")
  calls = []
  profiler_calls = []
  profiler_storage_failures = []
  seen = {}
  trace = TracePoint.new(:call, :b_call) do |event|
    if event.path.include?("/rack-mini-profiler-5.0.0/")
      key = [event.path.split("/rack-mini-profiler-5.0.0/", 2).last, event.lineno, event.method_id.to_s]
      profiler_calls << key unless profiler_calls.include?(key)
      if event.path.end_with?("/mini_profiler/config.rb") && event.binding.local_variable_defined?(:exception)
        exception = event.binding.local_variable_get(:exception)
        profiler_storage_failures << {class: exception.class.name, message: exception.message}
      end
    end
    next unless event.path.start_with?(File.expand_path(".") + "/")
    key = [event.path.delete_prefix(File.expand_path(".") + "/"), event.lineno, event.method_id, event.defined_class.to_s]
    unless seen[key]
      seen[key] = true
      calls << {source: key[0], line: key[1], method: key[2], owner: key[3]}
    end
  end
  response = profiler_proof = request_effects = nil
  request_env = Rack::MockRequest.env_for(url.to_s,
    "HTTP_HOST" => host, "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json")
  sql = FidelityDriver.capture do
    trace.enable
    response, profiler_proof, request_effects = LatestProfilerReferenceProbe.capture(request_env) do
      Rack::MockRequest.new(Rails.application).get(url.to_s, request_env)
    end
  ensure
    trace.disable
  end
  headers = response.headers.to_h
  body = JSON.parse(response.body)
  observation = {path: path, request_url: url.to_s, request_host: host,
    status: response.status, headers: headers, body: body,
    body_sha256: Digest::SHA256.hexdigest(response.body), sql: sql, original_calls: calls,
    profiler_calls: profiler_calls, profiler_storage_failures: profiler_storage_failures, profiler_proof: profiler_proof,
    request_effects: request_effects}
  File.binwrite(File.join(ENV.fetch("FIDELITY_JSON_REQUEST_REFERENCE_DIRECTORY"), "request-#{index}.json.response"), response.body)
  action_source = ListController.instance_method(:latest).source_location.first.delete_prefix(File.expand_path(".") + "/")
  raise "not the real list action" unless calls.any? { |call| call[:source] == action_source && call[:method] == :latest }
  if index == paths.length - 1
    raise "invalid page was not rejected" unless response.status == 400
  else
    raise "real latest request failed" unless response.status == 200
    raise "real full side-loaded payload missing" unless body.fetch("users").any? && body.fetch("topic_list").fetch("topics").any?
  end
  observations << observation
end
profiler = if defined?(Rack::MiniProfiler)
  config = Rack::MiniProfiler.config
  {version: Rack::MiniProfiler::VERSION, authorization_mode: config.authorization_mode,
   enabled: config.enabled, snapshot_every_n_requests: config.snapshot_every_n_requests,
   storage: config.storage_instance.class.name,
   preauthorized_empty_agent: !config.pre_authorize_cb || config.pre_authorize_cb.call({}),
   controller_profiler_class: ApplicationController::MINI_PROFILER_CLASS.to_s}
end
puts "FIDELITY_JSON_REQUEST_REFERENCE " + JSON.generate({
  profiler: profiler,
  profile: "GENUINE original core no-plugin Rails route/middleware/controller JSON; reference ONLY",
  requests: observations, native_request_accepted: false, json_request_accepted: false,
  full_query_accepted: false, page_accepted: false,
})
