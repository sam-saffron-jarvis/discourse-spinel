# An array of one user class is a PtrArray: its elements are pointers, not
# boxed values. Pushing onto it emitted the argument as written, so a value
# whose static type is poly went in as the whole sp_RbVal struct and the C did
# not compile (#4293).
#
# The shape that produces one: a method of that class whose return widened to
# poly because it answers its own argument and some call site passes a boxed
# one. `nodes << nodes.last.meld(x)` then pushes a poly into a Node array.

class N
  def m(o) = o
end

def widen(seed, kids)
  kids.reduce(seed) { |acc, kid| acc.m(kid) }
end

p widen(N.new, [nil, N.new].compact).class.to_s

nodes = [N.new]
nodes << nodes.last.m(N.new)
p nodes.length
p nodes.last.class.to_s

# nil through the same slot is a NULL element, which is how that array spells
# nil already
holes = [N.new]
holes << holes.last.m(nil)
p holes.length
p holes.last.nil?

# push / append / << all take the same path
a = [N.new]
a.push(a.last.m(N.new))
a.append(a.last.m(N.new))
a << a.last.m(N.new)
p a.length

# an ordinary object push is unchanged
b = [N.new]
b << N.new
p b.length
