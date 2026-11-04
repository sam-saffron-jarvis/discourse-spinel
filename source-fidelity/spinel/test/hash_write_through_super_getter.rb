# A getter that is just `super` answers the ancestor's ivar, so a write
# through it is evidence for that ivar: the ancestor's `def cache = @c`, an
# attr_reader, and `super()` two levels down.

class Base
  def initialize = @c = {}
  def cache = @c
  def put(k, v) = @c[k] = v
end
class Sub < Base
  def cache = super
end
s = Sub.new
s.put(1, 2)
s.cache["x"] = "y"
p s.cache

class RBase
  attr_reader :tbl
  def initialize = @tbl = {}
  def put(k, v) = @tbl[k] = v
end
class RMid < RBase
  def tbl = super()
end
class RLeaf < RMid
  def tbl = super
end
r = RLeaf.new
r.put(1, 2)
r.tbl[:k] = 1.5
p r.tbl, r.tbl[1] + 1

# a subclass getter over an ivar its base class writes
class Keeper
  def initialize = @c = {}
  def put(k, v) = @c[k] = v
end
class Shower < Keeper
  def cache = @c
end
k = Shower.new
k.put(1, 2)
k.cache[:k] = "v"
p k.cache
