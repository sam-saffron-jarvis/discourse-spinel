# A write through a getter whose value is `(@c ||= {})` is evidence for @c.
# Once @c is already a hash (typed by its own `@c[k] = v`), the write must be
# folded the way any getter write is, widening a hash it does not fit and
# the literals @c is assigned. Taking it as a direct `@c[k] = v` instead
# left @c an Integer-keyed hash that silently dropped a String key, or
# raised TypeError on a String value (#4902).
class RdDiff
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
  def outer = cache["x"] = "y"
  def show = @c
end
d = RdDiff.new
d.put(1, 2)
p d.outer
p d.show, d.show[1] + 1, d.show["x"]

class RdMixed
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
  def outer = cache[3] = "y"
  def show = @c
end
m = RdMixed.new
m.put(1, 2)
m.outer
p m.show, m.show[1] + 1, m.show[3]

class RdSame
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
  def outer = cache[3] = 4
  def show = @c
end
s = RdSame.new
s.put(1, 2)
s.outer
p s.show, s.show[1] + s.show[3]

class RdObj
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
  def show = @c
end
o = RdObj.new
o.put(1, 2)
o.cache["x"] = "y"
p o.show, o.show[1] + 1, o.show["x"]

class RdOnly
  def cache = (@c ||= {})
  def put(k, v) = cache[k] = v
  def show = @c
end
n = RdOnly.new
n.put(1, 2)
n.put(3, 4)
p n.show, n.show[1] + n.show[3]
