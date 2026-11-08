# frozen_string_literal: true
# TEST-only leaves exercise real response consumers, not settings/actors/routes.
require "json"

def middleware_response(kind, headers, body, env = {}, omit = false)
  app = lambda { |_env| [200, headers.dup, body.dup] }
  return app.call(env) if omit
  instance = if kind == "vary"
    MarkdownEndpoint::VaryMiddleware.new(app)
  elsif kind == "track"
    Middleware::TrackViewSessionIdInjector.new(app)
  else
    Middleware::CspScriptNonceInjector.new(app)
  end
  instance.call(env)
end

def assert_response(value, expected)
  raise "wrong genuine middleware response: #{value.inspect}" unless value == expected
end

vary_env = {"discourse.markdown_endpoint.vary_accept" => true}
[{}, {"Vary" => "Origin"}, {"vArY" => "origin, aCcEpT"}, {"Vary" => ",  ,\u00a0,Origin"}].each do |headers|
  before = headers.dup
  response = middleware_response("vary", headers, ["body"], vary_env)
  key = response[1].keys.find { |name| name.casecmp?("Vary") }
  tokens = response[1][key].split(",").map(&:strip)
  raise "Accept missing/duplicated" unless tokens.count { |token| token.casecmp?("Accept") } == 1
  raise "actual fast_blank non-ASCII token lost" if headers.values.any? { |value| value.include?("\u00a0") } && !tokens.include?("\u00a0")
  raise "leaf headers mutated" unless headers == before
end
assert_response(middleware_response("vary", {"Vary" => "Origin"}, ["body"]), [200, {"Vary" => "Origin"}, ["body"]])
raise "omitted Vary accepted" if middleware_response("vary", {}, ["body"], vary_env, true) == middleware_response("vary", {}, ["body"], vary_env)

track_header = "Discourse-Track-View-Session-Id-Placeholder"
tracked = middleware_response("track", {track_header => "TOKEN", "Other" => "kept"}, ["TOKEN TOKEN", "xTOKEN"])
raise "tracking placeholder leaked" if tracked[1].key?(track_header)
session_id = tracked[2][0].split(" ").first
raise "session id not original declared shape" unless session_id.length == 32 && session_id.match?(/\A[A-Za-z0-9]+\z/)
assert_response(tracked, [200, {"Other" => "kept"}, [session_id + " TOKEN", "x" + session_id]])
assert_response(middleware_response("track", {}, ["TOKEN"]), [200, {}, ["TOKEN"]])
raise "omitted tracking injector accepted" unless middleware_response("track", {track_header => "TOKEN"}, ["TOKEN"], {}, true)[1].key?(track_header)

nonce_header = "Discourse-CSP-Nonce-Placeholder"
policy = "default-src 'self'; script-src 'self';"
nonce = middleware_response("nonce", {nonce_header => "TOKEN", "Content-Security-Policy" => policy}, ["TOKEN TOKEN"])
nonce_value = nonce[2][0].split(" ").first
raise "nonce not original declared shape" unless nonce_value.length == 25 && nonce_value.match?(/\A[A-Za-z0-9]+\z/)
assert_response(nonce, [200, {"Content-Security-Policy" => "default-src 'self'; script-src 'nonce-#{nonce_value}' 'self';"}, [nonce_value + " " + nonce_value]])
fixed_headers = {nonce_header => "TOKEN", "Content-Security-Policy" => policy, "Content-Security-Policy-Report-Only" => policy}
fixed = middleware_response("nonce", fixed_headers, ["TOKEN"], {"discourse.csp_nonce" => "already-rendered"})
raise "existing nonce rewrote rendered body" unless fixed[2] == ["TOKEN"]
%w[Content-Security-Policy Content-Security-Policy-Report-Only].each do |name|
  raise "existing nonce policy missing" unless fixed[1][name].include?("script-src 'nonce-already-rendered' ")
end
blank_policy = middleware_response("nonce", {nonce_header => "TOKEN", "Content-Security-Policy" => "\u00a0"}, ["TOKEN"])
raise "blank CSP policy changed" unless blank_policy[1]["Content-Security-Policy"] == "\u00a0"
assert_response(middleware_response("nonce", {}, ["TOKEN"]), [200, {}, ["TOKEN"]])
raise "omitted nonce accepted" unless middleware_response("nonce", fixed_headers, ["TOKEN"], {}, true)[1].key?(nonce_header)

# Genuine order is Track OUTSIDE Nonce: Nonce substitutes every TOKEN first,
# leaving Track no matching body placeholder. Reversing them is observable.
leaf = lambda { |_env| [200, {track_header => "TOKEN", nonce_header => "TOKEN", "Content-Security-Policy" => policy}, ["TOKEN TOKEN"]] }
ordered = Middleware::TrackViewSessionIdInjector.new(Middleware::CspScriptNonceInjector.new(leaf)).call({})
parts = ordered[2][0].split(" ")
raise "real injector ordering changed" unless parts[0] == parts[1]
wrong = Middleware::CspScriptNonceInjector.new(Middleware::TrackViewSessionIdInjector.new(leaf)).call({})
wrong_parts = wrong[2][0].split(" ")
raise "reversed injector order accepted" unless wrong_parts[0].length == 32 && wrong_parts[1].length == 25
puts "PASS original response middleware effects, absence, actual fast_blank context, omitted and reversed-order negatives"
