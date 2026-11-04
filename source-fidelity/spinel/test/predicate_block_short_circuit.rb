# Predicate blocks stop as soon as their answer is determined. Check both
# the result and which elements the block visits.
values = [1, 2, 3]
seen = []
p [values.any? { |x| seen << x; x == 1 }, seen]
seen = []
p [values.none? { |x| seen << x; x == 1 }, seen]
seen = []
p [values.one? { |x| seen << x; x > 0 }, seen]
seen = []
p [values.all? { |x| seen << x; x < 1 }, seen]

# These answers require visiting the entire array.
seen = []
p [values.any? { |x| seen << x; x > 3 }, seen]
seen = []
p [values.none? { |x| seen << x; x > 3 }, seen]
seen = []
p [values.one? { |x| seen << x; x == 2 }, seen]
seen = []
p [values.all? { |x| seen << x; x > 0 }, seen]

# A block can shrink the receiver while returning either true or false.
shrinking = values.dup
seen = []
p [shrinking.all? { |x| seen << x; shrinking.pop; true }, seen]
shrinking = values.dup
seen = []
p [shrinking.all? { |x| seen << x; shrinking.clear; true }, seen]
shrinking = values.dup
seen = []
p [shrinking.all? { |x| seen << x; shrinking.clear; false }, seen]

# Exercise concrete truthy/falsy results and a result with a runtime type.
seen = []
p [values.all? { |x| seen << x; x - x }, seen]
seen = []
p [values.all? { |x| seen << x; nil }, seen]
mixed = [true, 0, nil, 4]
seen = []
p [mixed.all? { |x| seen << x; x }, seen]

# Empty array values take the loop path, not the empty-literal fold.
empty = values[0, 0]
seen = []
p [empty.any? { seen << 1; true },
   empty.none? { seen << 1; true },
   empty.one? { seen << 1; true },
   empty.all? { seen << 1; false }, seen]

# A next value must reach the stopping test, including Ruby truthiness.
seen = []
p [values.any? { |x| seen << x; next x - x; false }, seen]
seen = []
p [values.all? { |x| seen << x; next nil; true }, seen]

# A heterogeneous hash read makes the receiver boxed. This uses a separate
# predicate emitter, which needs the same stopping rules.
holder = { "values" => values, "empty" => empty,
           "shrinking" => values.dup, "label" => "array" }
boxed = holder["values"]
seen = []
p [boxed.any? { |x| seen << x; x == 1 }, seen]
seen = []
p [boxed.none? { |x| seen << x; x == 1 }, seen]
seen = []
p [boxed.one? { |x| seen << x; x > 0 }, seen]
seen = []
p [boxed.all? { |x| seen << x; x < 1 }, seen]

seen = []
p [boxed.any? { |x| seen << x; x > 3 }, seen]
seen = []
p [boxed.none? { |x| seen << x; x > 3 }, seen]
seen = []
p [boxed.one? { |x| seen << x; x == 2 }, seen]
seen = []
p [boxed.all? { |x| seen << x; x > 0 }, seen]

boxed_shrinking = holder["shrinking"]
seen = []
p [boxed_shrinking.all? { |x| seen << x; boxed_shrinking.clear; false }, seen]

boxed_empty = holder["empty"]
seen = []
p [boxed_empty.all? { seen << 1; false }, seen]

seen = []
p [boxed.any? { |x| seen << x; next x - x; false }, seen]
seen = []
p [boxed.all? { |x| seen << x; next nil; true }, seen]

# Ranges use the concrete-array loop after materialization.
seen = []
p [(1..3).one? { |x| seen << x; x > 0 }, seen]
