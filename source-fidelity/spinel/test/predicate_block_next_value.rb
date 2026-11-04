# `next <value>` leaves the block WITH that value, and for any? / all? /
# none? / one? that value is the predicate's answer. The fold emitted the
# leading statements and then the tail expression as the condition, so the
# next became a bare `continue` and the tail was read instead: the value was
# dropped and `any? { next true; false }` answered false (#4301).
#
# emit_block_value_into is the machinery for this -- it wraps the body so a
# next assigns the slot and falls through to the collection.

p([1, 2].any? { |i| next true if i == 1; false })
p([1, 2, 3].all? { |i| next true if i == 2; i.odd? })
p([1, 2].any? { |x| next false; true })
p([1, 2].none? { |x| next true })
p([1, 2].all? { |x| next nil })
p([1, 2, 3].one? { |x| next x == 2 })

# a next deeper in the body, and one that carries a computed value
p([1, 2, 3].any? { |x| if x > 2 then next x * 10 end; false })
p([1, 2, 3].all? { |x| next true if x.odd?; x.even? })

# blocks with no next are unchanged
p([1, 2].any? { |x| x == 1 })
p([1, 2].all? { |x| x > 0 })
p([1, 2].none? { |x| x > 5 })
p([1, 2, 3].one? { |x| x == 2 })
p([].any? { |x| true })
p([].all? { |x| false })

# a nested block owns its own next
p([[1, 2], [3]].any? { |row| row.any? { |x| next true if x == 3; false } })
