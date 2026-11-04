# A boxed Array's length can change while a predicate block runs. Removed
# elements must not be visited, and appended elements must be considered.
# Heterogeneous hash values keep the receivers boxed.
holder = { "all" => [1, 2, 3], "any" => [1, 2, 3],
           "none" => [1, 2, 3], "one" => [1, 2, 3], "label" => "array" }

a = holder["all"]
seen = []
p [a.all? { |x| seen << x; a.clear; true }, seen]
a = holder["any"]
seen = []
p [a.any? { |x| seen << x; a.clear; x.nil? }, seen]
a = holder["none"]
seen = []
p [a.none? { |x| seen << x; a.clear; x.nil? }, seen]
a = holder["one"]
seen = []
p [a.one? { |x| seen << x; a.clear; true }, seen]

# An appended element can change each predicate's answer.
holder = { "all" => [1], "any" => [1], "none" => [1], "one" => [1],
           "label" => "array" }
a = holder["all"]
seen = []
p [a.all? { |x| seen << x; a << 2 if x == 1; x == 1 }, seen]
a = holder["any"]
seen = []
p [a.any? { |x| seen << x; a << 2 if x == 1; x == 2 }, seen]
a = holder["none"]
seen = []
p [a.none? { |x| seen << x; a << 2 if x == 1; x == 2 }, seen]
a = holder["one"]
seen = []
p [a.one? { |x| seen << x; a << 2 if x == 1; true }, seen]

# Shrinking can also end traversal partway through the original array.
holder = { "values" => [1, 2, 3], "label" => "array" }
a = holder["values"]
seen = []
p [a.all? { |x| seen << x; a.pop; true }, seen]

# Mutation through another reference changes the same array's length.
original = [1, 2, 3]
holder = { "values" => original, "label" => "array" }
a = holder["values"]
seen = []
p [a.all? { |x| seen << x; original.clear; true }, seen]

# Other array storage kinds use the same boxed loop.
holder = { "strings" => ["a", "b"], "floats" => [1.0, 2.0],
           "mixed" => [true, nil, 0], "empty" => [1][0, 0] }
a = holder["strings"]
seen = []
p [a.all? { |x| seen << x; a.clear; x }, seen]
a = holder["floats"]
seen = []
p [a.all? { |x| seen << x; a.clear; x }, seen]
a = holder["mixed"]
seen = []
p [a.all? { |x| seen << x; a.clear; x }, seen]
a = holder["empty"]
seen = []
p [a.all? { seen << 1; false }, seen]

# A next value still reaches the predicate and the updated loop bound.
holder = { "values" => [1, 2, 3], "label" => "array" }
a = holder["values"]
seen = []
p [a.all? { |x| seen << x; a.clear; next true; false }, seen]

# Revisiting removed elements must not let a later block invocation raise.
holder = { "values" => [1, 2, 3], "label" => "array" }
a = holder["values"]
result = a.all? do |x|
  raise "visited a removed element" if x.nil?
  a.clear
  true
end
p result
