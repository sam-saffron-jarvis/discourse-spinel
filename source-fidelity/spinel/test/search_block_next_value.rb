# A `next <value>` leaves the block WITH that value; the searching and counting
# folds read the tail expression instead and dropped it (#4324).
p([1, 2].count { |i| next true if i == 1; false })
p([1, 2].find { |i| next true if i == 1; false })
p([1, 2].detect { |i| next true if i == 1; false })
p([1, 2].find_index { |i| next true if i == 1; false })
p([1, 2].index { |i| next true if i == 1; false })
p([1, 2].rindex { |i| next true if i == 1; false })
p([1, 2].take_while { |i| next true if i == 1; false })
p([1, 2].drop_while { |i| next true if i == 1; false })

# any truthy value carries, not just true, and a falsy one carries too
p([1, 2].count { |i| next 7 if i == 1; nil })
p([1, 2].find { |i| next nil if i == 1; true })

# a poly receiver takes a different set of folds
q = [1, "a", :b, 2]
p(q.count { |i| next true if i == 1; false })
p(q.find { |i| next true if i == 1; false })
p(q.find_index { |i| next true if i == 1; false })
p(q.take_while { |i| next true if i == 1; false })
p(q.drop_while { |i| next true if i == 1; false })

# and so does a string element
s = ["x", "yy"]
p(s.count { |t| next true if t.size == 1; false })
p(s.find { |t| next true if t.size == 1; false })
p(s.take_while { |t| next true if t.size == 1; false })

# a nested block owns its own next: this one answers the inner map, not the find
p([[1], [2]].find { |a| a.map { |x| next 0 if x == 1; x }.sum > 1 })
