# A yielding method whose body ends in `if block_given? ... else ... end` has
# two values, one per call form. The analyzer used to unify the arms, so a
# method answering a memo under a block and an Enumerator without one was
# poly for both callers; now a call with a block is typed from the block arm
# and a call without one from the else arm, and the inliner keeps only the arm
# the call site takes. The first shape builtins/enumerable.rb is written in.
def collect(xs, memo)
  if block_given?
    xs.each { |x| yield x, memo }
    memo
  else
    xs.map { |x| [x, memo] }.each
  end
end

a = collect([1, 2, 3], []) { |x, m| m << x * 2 }
p a
p a.size
e = collect([1, 2], [])
p e.class
p e.to_a

# the block arm ending in a yield is typed per call site, as a yield tail is
def pass(x)
  if block_given?
    yield x
  else
    x
  end
end
p pass(1) { |v| v.to_s }
p pass(2) { |v| v * 3 }
p pass(3)

# the guard as an early return
def early(xs)
  return xs.each unless block_given?
  xs.each { |x| yield x }
  xs.length
end
p early([1, 2]) { |x| x }
p early([1, 2]).class
