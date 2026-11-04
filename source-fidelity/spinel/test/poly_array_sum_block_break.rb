# sum { } on an Array of mixed classes whose block breaks answers the break
# value, as it does on an Integer array; a block without break still sums
# the mapped values (#4918).
p([1, "a", 3].sum { |x| break :early if x == 3; 1 })
p([1, "a", 3].sum { |x| break x if x.is_a?(String); 1 })
p([1, "a", 3].sum { |x| x.is_a?(Integer) ? x : 0 })
p([1, "a", 3].sum { |x| break 99 if x == :none; 2 })
p([1, 2, 3].sum { |x| break :early if x == 3; 1 })
