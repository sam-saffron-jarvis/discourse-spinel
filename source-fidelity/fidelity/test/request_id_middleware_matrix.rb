# frozen_string_literal: true
# Test the actual middleware boundary, including visibility BEFORE app entry.
require "json"

class RequestIdMiddlewareLeaf
  attr_reader :seen
  def initialize(rewrite = false, fail = false)
    @rewrite = rewrite
    @fail = fail
  end
  def call(env)
    @seen = env["action_dispatch.request_id"]
    env["action_dispatch.request_id"] = "reassigned-by-app" if @rewrite
    raise ArgumentError, "leaf failure" if @fail
    [201, {"X-Request-Id" => "stale-response"}, ["body"]]
  end
end

["", "   ", "\u00a0", "\u3000", "\u0000", "abc-DEF_1@x!y z", "!!!", "żółw-ab", "a" * 300].each do |value|
  env = {"HTTP_X_REQUEST_ID" => value}
  leaf = RequestIdMiddlewareLeaf.new
  response = RequestIdMiddlewareUnderTest.new(leaf, header: "X-Request-Id").call(env)
  id = env["action_dispatch.request_id"]
  raise "id not visible before app" unless !id.nil? && leaf.seen == id
  raise "header/env ID differ" unless response[1]["X-Request-Id"] == id
  raise "response changed" unless response[0] == 201 && response[2] == ["body"]
  expected_blank = FAST_BLANK_CONTEXT ? value.match?(/\A[\x00\x09-\x0d\x20]*\z/) : value.match?(/\A[[:space:]]*\z/)
  if expected_blank
    raise "blank id not original UUID shape" unless id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
  else
    expected = value.gsub(/[^\w\-@]/, "")[0, 255]
    raise "sanitization changed" unless id == expected
  end
end
custom = RequestIdMiddlewareLeaf.new
custom_env = {"HTTP_X_CUSTOM_TRACE" => "caller!@id", "HTTP_X_REQUEST_ID" => "wrong-header"}
custom_response = RequestIdMiddlewareUnderTest.new(custom, header: "X-Custom-Trace").call(custom_env)
raise "custom header binding ignored" unless custom.seen == "caller@id" && custom_response[1]["X-Custom-Trace"] == "caller@id"
rewritten = RequestIdMiddlewareUnderTest.new(RequestIdMiddlewareLeaf.new(true), header: "X-Request-Id").call({})
raise "request id read was prematurely captured" unless rewritten[1]["X-Request-Id"] == "reassigned-by-app"
failed_env = {}
begin
  RequestIdMiddlewareUnderTest.new(RequestIdMiddlewareLeaf.new(false, true), header: "X-Request-Id").call(failed_env)
  raise "app error swallowed"
rescue ArgumentError => error
  raise unless error.message == "leaf failure"
  raise "exception branch never assigned id" if failed_env["action_dispatch.request_id"].nil?
end
omitted = RequestIdMiddlewareLeaf.new
omitted.call({})
raise "omitted request-id consumer accepted" unless omitted.seen.nil?
puts "PASS actual request-id app-entry/env/header/Unicode/custom/error and omitted-consumer controls"
