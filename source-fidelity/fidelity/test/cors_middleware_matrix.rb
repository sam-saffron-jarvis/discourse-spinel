# frozen_string_literal: true
# Pure real CORS consumer controls; origins are caller inputs, not oracle data.
require "json"
cases = [
  [nil, {}, {}],
  [["https://a.invalid", "https://b.invalid"], {}, {}],
  [["https://a.invalid", "https://b.invalid"], {"HTTP_ORIGIN" => "https://b.invalid"}, {}],
  [["https://a.invalid", "https://b.invalid"], {"HTTP_ORIGIN" => "https://denied.invalid"}, {}],
  [["https://a.invalid"], {"HTTP_ORIGIN" => ""}, {}],
  [["https://a.invalid"], {}, {"Access-Control-Allow-Origin" => "already-controller-owned", "Other" => "kept"}]
]
results = []
cases.each do |origins, env, headers|
  original = headers.dup
  result = Discourse::Cors.apply_headers(origins, env, headers)
  raise "CORS header object replaced" unless result.equal?(headers)
  expected_origin = if original["Access-Control-Allow-Origin"]
    original["Access-Control-Allow-Origin"]
  elsif origins
    origin = env["HTTP_ORIGIN"]
    origin && origins.include?(origin) ? origin : origins[0]
  end
  raise "origin selection changed" unless headers["Access-Control-Allow-Origin"] == expected_origin
  if origins && !original["Access-Control-Allow-Origin"]
    raise "credentials header missing" unless headers["Access-Control-Allow-Credentials"] == "true"
    raise "method list changed" unless headers["Access-Control-Allow-Methods"] == "POST, PUT, GET, OPTIONS, DELETE"
    raise "max age changed" unless headers["Access-Control-Max-Age"] == "7200"
    raise "auth header declaration lost" unless headers["Access-Control-Allow-Headers"].include?("User-Api-Key")
    raise "omitted CORS consumer accepted" if original == headers
    wrong = headers.dup
    wrong["Access-Control-Allow-Origin"] = "https://wrong.invalid"
    raise "wrong CORS origin accepted" if wrong == headers
  else
    raise "preexisting/disabled headers changed" unless original == headers
  end
  results << headers
end
puts JSON.generate(results)
puts "PASS actual CORS origin selection, fallback, controller precedence, credentials and omitted/wrong controls"
