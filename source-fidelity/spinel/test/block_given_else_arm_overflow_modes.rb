# The else arm of an `if block_given?` tail is what a blockless call answers,
# and under --int-overflow=promote the method's Integer locals are widened to
# boxed slots after the fixpoint. That blockless answer widens with them: it
# used to stay sp_int while the arm computed on the boxed parameter, and the
# C build failed in promote mode (#4659). The output is the same in every
# overflow mode.
def maybe_yield(x)
  if block_given?
    yield x
  else
    x * 2
  end
end
puts maybe_yield(5)
p maybe_yield(5) { |n| n * 3 }
def scale(x, k)
  if block_given?
    yield(x * k)
  else
    x * k + 1
  end
end
puts scale(6, 7)
puts scale(6, 7) { |v| v - 1 }
r = maybe_yield(4)
puts r + 1
puts maybe_yield(4_000_000_000) * 2
