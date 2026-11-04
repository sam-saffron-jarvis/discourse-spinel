# A proc's parameter is typed from its `.call` sites, and a parameter that
# settles LATE leaves the caller-side proc_ret derived from the body as it
# read BEFORE -- so the call site unboxes the wrong channel.
#
# An empty-array local is the late case: `e = []` types the parameter only in
# the post-convergence pass, by which time proc_ret had already been taken
# with the parameter at its int default. The body plainly builds an array, and
# the call answered an Integer (#4296).
#
# The re-derivation that fixes it existed for --int-overflow=promote, which
# widens a body the same way after the fixpoint; it runs unconditionally now.

f = ->(acc) { acc + [1] }
e = []
p f.call(e)
p f.call(e).class.to_s

# a second, typed call site always worked -- it types the parameter early
g = ->(acc) { acc + [1] }
h = []
p g.call(h)
p g.call([2])

# the same shape through a proc rather than a lambda
k = proc { |acc| acc + [9] }
m = []
p k.call(m)

# an empty hash local, the other late one
hs = ->(h2) { h2.size }
eh = {}
p hs.call(eh)

# scalar and typed parameters are unchanged
n = ->(x) { x * 2 }
p n.call(3)
p n.call("ab")
s = ->(a) { a.size }
p s.call([1, 2, 3])
