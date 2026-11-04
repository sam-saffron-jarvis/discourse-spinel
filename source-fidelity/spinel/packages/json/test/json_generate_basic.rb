require "json"
# JSON.generate over the common Hash/Array/scalar shapes. Compact
# form, `:` separators, nil->null, symbol/int keys coerced to strings,
# JSON string escaping. Nested structures recurse.
puts JSON.generate({"x" => "y"})
puts JSON.generate({"a" => 1, "b" => 2})
puts JSON.generate({a: 1, b: 2})
puts JSON.generate({a: "hi"})
puts JSON.generate({"a" => [1, 2, 3], "b" => 5})
puts JSON.generate({a: nil, b: true, c: false})
puts JSON.generate([1, 2, 3])
puts JSON.generate(["x", "y"])
puts JSON.generate({"k" => "a\"b\nc\td"})
puts JSON.generate({"nested" => {"x" => 1}})
puts JSON.generate(42)
puts JSON.dump({"d" => "dump"})
