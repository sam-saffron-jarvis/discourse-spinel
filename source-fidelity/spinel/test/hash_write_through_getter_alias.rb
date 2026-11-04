# A local that holds what a getter (or the ivar itself) answers is that
# hash, not a copy: an index write through the local is evidence for the
# ivar, as a write through the getter would be.

class C
  def initialize = @c = {}
  def put(k, v) = @c[k] = v
  def cache = @c
end
c = C.new; c.put(1, 2); x = c.cache; x["x"] = "y"; p c.cache

class D
  def initialize = @d = {}
  def put(k, v) = @d[k] = v
  def fill
    h = @d
    h[:s] = "sym"
  end
  def own
    t = tbl
    t["t"] = 3
  end
  def tbl = @d
end
d = D.new
d.put(1, 2)
d.fill
d.own
p d.tbl, d.tbl[1] + d.tbl["t"]
