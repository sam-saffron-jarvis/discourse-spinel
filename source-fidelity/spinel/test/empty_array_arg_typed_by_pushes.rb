# An empty `[]` handed to a yielding method takes the element kind the method
# pushes into it, directly or through the block parameter it yields it as.
# The literal carries no kind of its own and used to stay a boxed array here;
# `x = []; x << 1` narrowed, `f([]) { |m| m << 1 }` did not.
def fill(memo)
  memo << 1
  memo << 2
  memo
end
a = fill([])
p a

def via_yield(memo)
  yield memo
  memo
end
b = via_yield([]) { |m| m << 3 }
p b

def spread(xs, memo)
  xs.each { |x| yield x, memo }
  memo
end
c = spread([1, 2], []) { |x, m| m << x * 10 }
p c
d = spread(["a", "b"], []) { |x, m| m << x.upcase }
p d
f = spread([1, 2], []) { |x, m| m << x / 2.0 }
p f
# a mixed push stays boxed
g = spread([1, 2], []) { |x, m| m << x; m << x.to_s }
p g
