# frozen_string_literal: true
# Explicit UNIT-only serialization vectors. Never cache/request production input.
require "json"
require "base64"
cases = [[], [{url: "https://unit.invalid/theme.js", theme_id: -987654, external_plugin_imports: ["unit-only-plugin"]}]]
cases.each do |value|
  bytes = Marshal.dump(value)
  encoded = Base64.encode64(bytes)
  decoded = Marshal.load(Base64.decode64(encoded))
  raise "unit Marshal did not round-trip Array" unless decoded == value && decoded.is_a?(Array)
  puts "FIDELITY_UNIT_THEME_MARSHAL " + JSON.generate({encoded: encoded, value: value, decoded: decoded, ruby_class: decoded.class.name, unit_only: true})
end
