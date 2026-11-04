# `obj.attr ||= <value>` through a hand-written writer: the value temp must be
# declared with a type that can hold what the emitter renders into it.
# An empty container literal has no type of its own -- comp_ntype answers poly
# and the emitter picks the concrete container from how the attribute is used
# later -- so the temp was declared sp_RbVal and initialized with an
# sp_IntArray *, which did not compile. A literal nil declared a `void` temp
# for the same reason (emit_ctype spells TY_NIL that way).

class U
  def initialize
    @h = {}
    @calls = 0
  end

  def g
    @h["k"]
  end

  def g=(v)
    @calls += 1
    @h["k"] = v
  end

  def calls
    @calls
  end
end

u = U.new
u.g ||= []
u.g.push(1)
puts u.g.length
puts u.calls

# the writer runs once, and not again once the reader answers truthy
u.g ||= [7, 8]
puts u.g.length
puts u.calls

# an empty Hash literal takes the same path
h = U.new
h.g ||= {}
h.g["a"] = 1
puts h.g.length

# a literal nil is a value, not an absent one
n = U.new
n.g ||= nil
p n.g
puts n.calls

# `&&=` shares the emission: the reader is nil, so nothing is assigned and
# nothing is evaluated on the right
a = U.new
a.g &&= []
p a.g
puts a.calls

# and it does assign once the reader is truthy
b = U.new
b.g ||= [1]
b.g &&= [2, 3]
puts b.g.length
puts b.calls
