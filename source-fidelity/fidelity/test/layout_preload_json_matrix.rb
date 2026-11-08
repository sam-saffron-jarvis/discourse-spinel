# frozen_string_literal: true
require "json"
# This is a supplied unit preloader of strings, not ApplicationLayoutPreloader,
# real Site/settings/theme state, or an original Rails HTML response.
class UnitLayoutPreloader
  attr_reader :reads
  def initialize(data)
    @data = data
    @reads = 0
  end
  def preloaded_data
    @reads += 1
    @data
  end
end
class UnitLayoutHelper
  include PortableLayoutPreloadMethods
  def initialize(preloader)
    @application_layout_preloader = preloader
  end
end
empty = UnitLayoutHelper.new(nil)
raise "nil preloader changed" unless empty.preloaded_json == "{}"
inputs = ["</script><script>unit injection</script>", "line\u2028separator", "line\u2029separator",
          "quotes\"\\ and &<>雪", nil, "", "prefix\xFFsuffix".dup.force_encoding("UTF-8")]
inputs.each do |value|
  data = {"unit-value" => value, "nested-json-string" => '{"unit":"</script>"}'}
  original_bytes = value.nil? ? [] : value.bytes
  preloader = UnitLayoutPreloader.new(data)
  helper = UnitLayoutHelper.new(preloader)
  text = helper.preloaded_json
  raise "wrong JSON result type" unless text.is_a?(String)
  raise "preloader acquisition omitted/repeated" unless preloader.reads == 1
  parsed = JSON.parse(text)
  raise "wrong result types" unless parsed.is_a?(Hash) && parsed["unit-value"].is_a?(String)
  raise "input mutated" unless value.nil? || original_bytes == value.bytes
  raise "literal script closer leaked" if text.include?("</")
  raise "literal line separator leaked" if text.include?("\u2028")
  raise "nested JSON string was converted to a non-string" unless parsed["nested-json-string"].is_a?(String)
  expected = value.nil? ? "" : value.scrub.gsub("\u2028", "&#x2028;").gsub("</", '\u003C/')
  raise "escape semantics changed" unless parsed["unit-value"] == expected
  raise "new output captured old preloader" unless helper.preloaded_json == text && preloader.reads == 2
  puts JSON.generate({input_bytes: original_bytes, json: text, type: "String", reads: preloader.reads})
end
puts "PASS exact source preload JSON acquisition/type/script-closer/unicode/scrub/mutation controls in standalone JSON unit context"
