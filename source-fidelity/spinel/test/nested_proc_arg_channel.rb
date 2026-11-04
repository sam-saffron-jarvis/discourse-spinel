# An argument that is itself a proc call writes -- and its callee's prologue
# then clears -- the same boxed side channel the outer call is publishing into,
# so `step.call(acc, fn.call(input))` lost acc and it arrived nil (#4333).
def mapping(fn)
  ->(step) { ->(acc, input) { step.call(acc, fn.call(input)) } }
end

conj = ->(acc, x) { acc + [x] }
r = mapping(->(n) { n * 3 }).call(conj)
p r.call([], 1)
p mapping(->(n) { n * 3 }).call(conj).call([], 1)

sum = ->(acc, x) { acc + x }
p mapping(->(n) { n * 3 }).call(sum).call(0, 2)

cat = ->(acc, x) { acc + x.to_s }
p mapping(->(n) { n * 3 }).call(cat).call("", 4)

# Proc#[] is #call, so its operands are the proc's -- not a two-integer slice
def taking(fn)
  ->(step) { ->(acc, input) { step[acc, fn[input]] } }
end
p taking(->(n) { n + 1 }).call(conj).call([], 1)
p taking(->(n) { n + 1 }).call(sum).call(0, 1)

# a slice on a genuinely boxed array still slices
def slice_of(v)
  v[1, 2]
end
p slice_of([1, 2, 3, 4])
p slice_of("abcd")
