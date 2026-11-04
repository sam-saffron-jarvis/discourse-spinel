# A block that leaves early with `next v` and falls through to `nil` answers
# the v where it took the `next`. The splice the yield reads was typed from
# the block's TAIL alone, so a tail of `nil` made the whole splice nil-typed
# -- and the nil arm of the boxing hands back a constant, throwing the value
# the block actually produced away. The block's `next` values are part of
# what it can answer, so the type unifies them, the way the analysis already
# does for the yield itself.
def each_yield(arr)
  arr.each { |e| r = yield e; p r }
end
each_yield([1, 2]) { |i| next 7 if i == 1; nil }

# the same with the yield outside a block of its own
def once
  r = yield 1
  p r
end
once { |i| next 7 if i == 1; nil }

# a tail that is not nil was never affected, and still is not
each_yield([1, 2]) { |i| next 7 if i == 1; 0 }

# neither was a block with no `next` at all
each_yield([1, 2]) { |i| i == 1 ? 7 : nil }

# a bare `next` still answers nil, and a `next` carrying something that is not
# an Integer still answers that
each_yield([1, 2]) { |i| next if i == 1; 5 }
each_yield([1, 2]) { |i| next "s" if i == 1; nil }
each_yield([1, 2]) { |i| next [1, 2] if i == 1; nil }

# a `break` in the same position is NOT the block's value: it leaves the
# ITERATOR, so what it carries is the iterator call's answer. Counting it here
# would widen the block and put the wrong C type in the splice.
def upto3
  r = nil
  [1, 2, 3].each { |i| r = yield i }
  r
end
p(upto3 { |i| next 7 if i == 1; nil })
p([1, 2, 3].each { |i| break "stopped" if i == 2 })

# the value is not discarded when it is consumed rather than printed
def sum_yield(arr)
  t = 0
  arr.each { |e| v = yield e; t += v.to_i }
  t
end
p sum_yield([1, 2, 3]) { |i| next 10 if i.odd?; nil }
