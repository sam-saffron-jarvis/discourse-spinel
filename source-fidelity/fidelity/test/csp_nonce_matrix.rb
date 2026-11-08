# frozen_string_literal: true
# Supplied unit headers/env/policy only. Randomness is genuine, never a fixed
# replacement for SecureRandom. Assertions run BEFORE output normalization.
class UnitNonceRequest
  attr_reader :env
  def initialize(env)
    @env = env
  end
end
class UnitNonceResponse
  attr_reader :headers
  def initialize(headers)
    @headers = headers
  end
end
class UnitNonceHelper < UnitAssetHelper
  include UnitCspNonceMethod
  attr_reader :request, :response
  def initialize(env, headers)
    super({}, {}, "unused-unit-context-field")
    @request = UnitNonceRequest.new(env)
    @response = UnitNonceResponse.new(headers)
  end
end
cache_key = Middleware::AnonymousCache::CACHEABLE_ENV
nonce_key = Middleware::CspScriptNonceInjector::NONCE_ENV
placeholder_header = Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER
seen = []
["nil-env", "cached", "uncached", "existing-env-nonce", "existing-header"].each do |mode|
  env = if mode == "nil-env" || mode == "existing-header"
    nil
  elsif mode == "cached"
    {cache_key => true}
  elsif mode == "existing-env-nonce"
    {cache_key => false, nonce_key => "unit-existing-nonce"}
  else
    {cache_key => false}
  end
  policy = "default-src 'self'; script-src 'self'; script-src https://unit.invalid"
  report = "script-src 'self'; report-uri /unit-csp-report"
  headers = {"Content-Type" => "text/html", "Content-Security-Policy" => policy,
             "Content-Security-Policy-Report-Only" => report}
  headers[placeholder_header] = "unit-existing-placeholder" if mode == "existing-header"
  helper = UnitNonceHelper.new(env, headers)
  first = helper.csp_nonce_placeholder
  raise "nonce placeholder was not memoized" unless first == helper.csp_nonce_placeholder
  if mode == "nil-env" || mode == "cached"
    raise "bad real placeholder entropy/shape" unless first.match?(/\A\[\[csp_nonce_placeholder_[0-9a-f]{32}\]\]\z/)
  elsif mode == "uncached"
    raise "bad generated env nonce" unless first.match?(/\A[a-zA-Z0-9]{25}\z/) && env[nonce_key] == first
  elsif mode == "existing-env-nonce"
    raise "existing env nonce lost" unless first == "unit-existing-nonce"
  else
    raise "existing header lost" unless first == "unit-existing-placeholder"
  end
  fragment = helper.preload_script_url("/unit-one.js", type_module: true, attrs: {"data-unit" => "<&"})
  second = helper.preload_script_url("/unit-two.js")
  # Exact original helper output, including typed safe-result checks.
  first_row = fragment_record(fragment)
  second_row = fragment_record(second)
  body = [first_row.fetch(:text), second_row.fetch(:text)]
  request_env = env || {}
  app = lambda { |actual| raise "env identity changed" unless actual.equal?(request_env); [200, headers, body] }
  status, actual_headers, parts = Middleware::CspScriptNonceInjector.new(app).call(request_env)
  raise "status changed" unless status == 200
  raise "private placeholder header leaked" if actual_headers.key?(placeholder_header)
  nonce = parts.first[/nonce="([^"]+)"/, 1]
  raise "missing nonce" unless nonce
  if mode == "existing-env-nonce"
    raise "explicit env nonce changed" unless nonce == "unit-existing-nonce"
  else
    raise "bad actual nonce entropy/shape" unless nonce.match?(/\A[a-zA-Z0-9]{25}\z/)
    raise "reused actual random nonce" if seen.include?(nonce)
    seen << nonce
  end
  raise "body nonce mismatch" unless parts.all? { |part| part.include?("nonce=\"#{nonce}\"") }
  raise "placeholder body leaked" if first != nonce && parts.any? { |part| part.include?(first) }
  raise "enforced CSP nonce wrong" unless actual_headers["Content-Security-Policy"] == policy.sub("script-src ", "script-src 'nonce-#{nonce}' ")
  raise "report-only CSP nonce wrong" unless actual_headers["Content-Security-Policy-Report-Only"] == report.sub("script-src ", "script-src 'nonce-#{nonce}' ")
  expected_identity = !!request_env[nonce_key]
  raise "response identity semantics changed" unless parts.equal?(body) == expected_identity
  raise "resource side effect omitted" unless helper.asset_preload_links == ["</unit-one.js>; rel=\"preload\"; as=\"script\"", "</unit-two.js>; rel=\"preload\"; as=\"script\""]
  puts JSON.generate({mode: mode, status: status,
    headers: actual_headers.transform_values { |value| value.gsub(nonce, "UNIT_NORMALIZED_NONCE") },
    parts: parts.map { |part| part.gsub(nonce, "UNIT_NORMALIZED_NONCE") },
    same_body: parts.equal?(body), safe_type: first_row.fetch(:kind), links: helper.asset_preload_links})
end
# No marker means no body/headers mutation or nonce generation.
empty_env = {}
headers = {"Content-Security-Policy" => "script-src 'self'"}
body = ["unit raw body"]
app = lambda { |_env| [201, headers, body] }
result = Middleware::CspScriptNonceInjector.new(app).call(empty_env)
raise "no-marker passthrough changed" unless result == [201, headers, body] && result[2].equal?(body) && empty_env.empty?
# The application uses fast_blank: NUL/ASCII whitespace is blank, NBSP is not.
["", " \t\n", "\0", "\u00a0"].each do |policy|
  env = {nonce_key => "unit-existing-nonce"}
  headers = {placeholder_header => "unit-existing-nonce", "Content-Security-Policy" => policy}
  body = ["unit body"]
  app = lambda { |_env| [200, headers, body] }
  status, actual, parts = Middleware::CspScriptNonceInjector.new(app).call(env)
  raise "blank-policy behavior changed" unless status == 200 && actual["Content-Security-Policy"] == policy && parts.equal?(body)
  raise "marker leaked for blank policy" if actual.key?(placeholder_header)
end
# Failed expectation controls: wrong nonce/body/CSP substitutions cannot pass
# the exact checks used above, nor can an ordinary String stand for trusted HTML.
raise "plain string treated as helper result" if unit_safe_result?("<script>untrusted</script>")
puts "PASS genuine nonce generation/memoization/substitution/CSP/env/body identity and unit helper integration"
