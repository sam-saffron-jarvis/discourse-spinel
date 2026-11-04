# `sum(init) { }` renders its initial value into the accumulator's declaration.
# That value was written straight into the prelude buffer the declaration is
# being built in, so a value needing construction statements -- an empty array
# literal, which hoists `sp_PolyArray_new()` and its root -- landed in the
# MIDDLE of the line:
#
#   sp_RbVal _t2 = sp_box_nullable_obj((void *)(  sp_PolyArray *_t7 = ...;
#
# and the program did not compile. The receiver beside it already rendered
# through a side buffer first; the initial value does now too.

p({ a: [1], b: [2] }.sum([]) { |_k, v| v })
p([[1], [2]].sum([]) { |v| v })

# a non-empty array initial value needs the same hoist
p({ a: [1], b: [2] }.sum([9]) { |_k, v| v })

# an empty Hash literal is the other constructing literal; Hash has no #+, so
# the sum itself raises in both -- what matters here is that the C compiles,
# so the raise is caught rather than printed (its text carries a backtrace
# whose format differs)
begin
  [{ a: 1 }, { b: 2 }].sum({}) { |h| h }
rescue NoMethodError
  p "hash init compiled and raised"
end

# initial values that need no construction are unchanged
p({ a: 1, b: 2 }.sum(0) { |_k, v| v })
p({ a: 1, b: 2 }.sum { |_k, v| v })
p({ a: "x", b: "y" }.sum("") { |_k, v| v })

# the folds that share this emitter keep their shapes
p([1, 2, 3].sum { |v| v * 2 })
p([1, 2, 3].count { |v| v > 1 })
p([1, 2, 3].all? { |v| v > 0 })
p([1, 2, 3].any? { |v| v > 2 })
p([1, 2, 3].none? { |v| v > 5 })
p([1, 2, 3].one? { |v| v == 2 })
