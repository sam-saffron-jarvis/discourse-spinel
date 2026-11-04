# A direct `@c[k] = v` whose key the ivar's hash cannot hold -- other sites,
# here writes through an `(@c ||= {})` getter, settled it Integer-keyed --
# widens the hash, as the same write through the getter would.

class C
  def c = (@c ||= {})
  def put_g(k, v) = c[k] = v
  def put_d(k, v) = @c[k] = v
end
o = C.new
o.put_g(1, 2)
o.put_d(:s, 3.5)
o.put_g(4, 5)
p o.c, o.c[1] + o.c[4], o.c[:s]

class E
  def initialize = @h = {}
  def h = @h
  def put_d(k, v) = @h[k] = v
end
e = E.new
e.h[1] = 2
e.put_d("s", "t")
p e.h, e.h[1] + 1
