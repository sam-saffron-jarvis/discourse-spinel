# An index write or push through a getter is evidence for the ivar the getter
# returns, as `@c[k] = v` in its class would be (#4893): an attr_reader, a
# `def cache = @c`, an `||=` getter, a getter with an early return, a
# class-side getter, a subclass override returning another ivar and a getter
# from an included module, called on self or on an object.

class Plain
  def initialize = @c = {}
  def cache = @c
  def put(k, v) = @c[k] = v
  def outer = cache["s"] = "self"
  def show = @c
end
pl = Plain.new
pl.put(1, 2)
pl.cache["x"] = "y"
pl.outer
p pl.show, pl.show[1] + 1, pl.show["x"]

class Reader
  attr_reader :cache
  def initialize = @cache = {}
  def put(k, v) = @cache[k] = v
end
r = Reader.new
r.put(1, 2)
r.cache[3] = "mixed"
p r.cache, r.cache[1] + 1

class Accessor
  attr_accessor :cache
  def initialize = @cache = {}
  def put(k, v) = @cache[k] = v
end
ac = Accessor.new
ac.put(1, 2)
p(ac.cache["v"] = "value")
p ac.cache

class OrWrite
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
end
ow = OrWrite.new
ow.put(1, 2)
ow.cache["x"] = "y"
ow.cache["z"] ||= "w"
p ow.cache

class Early
  def initialize(first) = (@first = first; @a = {}; @b = {})
  def tbl
    return @a if @first
    @b
  end
  def seed = (@a[1] = 2; @b[1] = 2)
  def show = [@a, @b]
end
e1 = Early.new(true); e1.seed; e1.tbl["x"] = "y"
e2 = Early.new(false); e2.seed; e2.tbl["z"] = "w"
p e1.show, e2.show

class Same
  attr_reader :counts
  def initialize = @counts = {}
  def add(w) = @counts[w] = (@counts[w] || 0) + 1
end
sm = Same.new
%w[a b a].each { |w| sm.add(w) }
sm.counts["z"] = 10
p sm.counts, sm.counts["a"] + 1

class ClassSide
  def self.cache = @c
  def self.seed
    @c = {}
    @c[1] = 2
  end
  def self.outer = cache[:k] = [1]
  def self.show = @c
end
ClassSide.seed
ClassSide.cache["x"] = "y"
ClassSide.outer
p ClassSide.show, ClassSide.show[1] + 1

class Base
  def initialize
    @a = {}
    @b = {}
  end
  def cache = @a
  def put(k, v) = @a[k] = v
  def outer = cache["s"] = "self"
  def show_a = @a
end
class Sub < Base
  def cache = @b
  def seed = @b[1] = 2
  def show_b = @b
end
b = Base.new
b.put(1, 2)
s = Sub.new
s.put(1, 2)
s.seed
s.outer
b.cache[5] = "b"
p b.show_a, s.show_a, s.show_b, s.show_b[1] + 1, s.show_a[1] + 1

module Cached
  def cache = @c
end
class WithModule
  include Cached
  def initialize = @c = {}
  def put(k, v) = @c[k] = v
end
wm = WithModule.new
wm.put(1, 2)
wm.cache["x"] = "y"
p wm.cache

class Inherited < Plain; end
ih = Inherited.new
ih.put(1, 2)
ih.cache[:sym] = 1.5
p ih.show

class Arr
  def initialize = @a = []
  def arr = @a
  def put(v) = @a << v
end
ar = Arr.new
ar.put(1)
ar.put(2)
ar.arr << "s"
ar.arr[1] = :t
p ar.arr, ar.arr[0] + 1

class LazyArr
  def arr = (@a ||= [])
  def put(v) = arr << v
end
la = LazyArr.new
la.put(1)
la.arr << "s"
p la.arr

class ClassList
  @list = []
  def self.list = @list
  def self.add(x) = @list << x
end
ClassList.add(1)
ClassList.list << "s"
p ClassList.list

class Nonempty
  def initialize = @c = {1 => 2}
  def cache = @c
end
ne = Nonempty.new
ne.cache["x"] = "y"
p ne.cache

# A Symbol key is the only foreign write: Integer- and String-keyed hashes,
# with a value that fits and one that does not.
class SymIntFit
  def initialize = @c = {}
  def cache = @c
  def put(k, v) = @c[k] = v
end
sif = SymIntFit.new
sif.put(1, 2)
sif.cache[:k] = 3
p sif.cache, sif.cache[:k], sif.cache[1] + 1

class SymIntMisfit
  def initialize = @c = {}
  def cache = @c
  def put(k, v) = @c[k] = v
  def outer = cache[:k] = "v"
end
sim = SymIntMisfit.new
sim.put(1, 2)
sim.outer
p sim.cache, sim.cache[:k], sim.cache[1] + 1

class SymStrFit
  attr_reader :cache
  def initialize = @cache = {}
  def put(k, v) = @cache[k] = v
end
ssf = SymStrFit.new
ssf.put("a", "b")
ssf.cache[:k] = "c"
p ssf.cache, ssf.cache[:k], ssf.cache["a"]

class SymStrMisfit
  def initialize = @c = {}
  def cache = (@c ||= {})
  def put(k, v) = @c[k] = v
end
ssm = SymStrMisfit.new
ssm.put("a", 2)
ssm.cache[:k] = "v"
p ssm.cache, ssm.cache[:k], ssm.cache["a"] + 1
