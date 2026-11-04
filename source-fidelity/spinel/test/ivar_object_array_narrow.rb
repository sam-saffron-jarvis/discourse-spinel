# An @ivar holding a homogeneous array of one user class narrows to the
# unboxed pointer array (sp_PtrArray) the way a local already did, when every
# reference to it is one the representation has an emitter for: index, []=,
# push, length, empty?, first/last, no-block sort/min/max (the class has
# <=>), a local alias, and its attr_reader read on a receiver statically of
# the class. optcarrot's shape from #4444: `h.items[i].x` in a hot loop paid
# a cls_id switch per field read because `@items` stayed a poly array.
class Vec
  attr_reader :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
  def sum = @x + @y
  def to_s = "(#{@x},#{@y})"
  def <=>(o) = sum <=> o.sum
end

# narrowed: every use is modeled
class Holder
  attr_reader :items
  def initialize(n)
    @items = Array.new(n) { |i| Vec.new(i, i * 2) }
  end
  def add(v)
    @items << v
    @items.push(Vec.new(9, 9))
  end
  def replace(i, v)
    @items[i] = v
  end
  def total
    t = 0
    i = 0
    while i < @items.length
      t += @items[i].sum
      i += 1
    end
    t
  end
  def smallest = @items.min.to_s
  def largest = @items.max.to_s
  def ordered
    a = @items
    a.sort!
    a.first.to_s + " " + a.last.to_s
  end
  def blank? = @items.empty?
end

h = Holder.new(4)
h.add(Vec.new(3, 3))
puts h.total
puts h.replace(0, Vec.new(7, 7))
puts h.smallest
puts h.largest
puts h.ordered
puts h.blank?
puts h.items.size
puts h.items[1]
puts h.items[100].inspect
# the default inspect walks the narrowed ivar through each element's own
puts Holder.new(2).inspect.sub(/0x[0-9a-f]+/, "ADDR").gsub(/Vec:0x[0-9a-f]+/, "Vec:ADDR")
i = 0
tot = 0
while i < h.items.length
  v = h.items[i]
  tot += v.x + v.y
  i += 1
end
puts tot

# an explicit reader method is a return slot: the ivar joins its component
# through the method's tail expression, and a caller's local aliases it
class Bag
  def initialize
    @vs = []
    @vs << Vec.new(1, 1)
  end
  def vs = @vs
end
b = Bag.new
bv = b.vs
bv << Vec.new(2, 2)
puts bv.length
puts bv[1]

# kept boxed: a block iteration over the ivar (no emitter for it). Each class
# below names its ivar differently: a symbol or a dynamic receiver is attributed
# by name alone and would keep every same-named slot boxed.
class Walker
  attr_reader :ws
  def initialize = @ws = [Vec.new(1, 2), Vec.new(3, 4)]
  def names = @ws.map(&:to_s).join(",")
end
w = Walker.new
puts w.names
puts w.ws[0]

# kept boxed: the reader answers a dynamic receiver
class Dyn
  attr_reader :ds
  def initialize = @ds = [Vec.new(5, 5)]
end
slot = [Dyn.new, "x"]
puts slot[0].ds.length
puts slot[0].ds.map(&:to_s).inspect

# kept boxed: a symbol names the ivar (instance_variable_get)
class Named
  def initialize = @ns = [Vec.new(6, 6)]
  def peek = instance_variable_get(:@ns).length
  def one = @ns[0]
end
puts Named.new.peek
puts Named.new.one

# kept boxed: a subclass exists (its methods could read the slot unvetted)
class Base
  attr_reader :bs
  def initialize = @bs = [Vec.new(8, 8)]
end
class Derived < Base
  def sum_all
    s = 0
    @bs.each { |v| s += v.sum }
    s
  end
end
puts Derived.new.sum_all
puts Base.new.bs[0]

# kept boxed: an attr_accessor is a writer
class Open
  attr_accessor :os
  def initialize = @os = [Vec.new(1, 0)]
end
o = Open.new
o.os = [1, "two"]
puts o.os.inspect

# kept boxed: the ivar escapes as an argument
class Leaky
  def initialize = @ls = [Vec.new(2, 0)]
  def dump = p(@ls.length)
  def hand = helper(@ls)
  def helper(a) = a.map(&:x).inspect
end
Leaky.new.dump
puts Leaky.new.hand

# Two holes the same pass had for locals. A method whose body is `c << x`
# answers the array itself: its return followed its parameter to the pointer
# array only when the argument was typed early, and with an empty local it
# kept the poly-array return over a pointer-array body (the C did not
# compile). And a foreign element stored with `[]=` was "no evidence" rather
# than a conflict, so the array narrowed and the store initialised a Vec
# pointer from a String.
def add_to(collection) = collection << Vec.new(4, 4)
acc = []
add_to(acc)
r = add_to(acc)
puts acc.length
puts r.length
mixed = [Vec.new(1, 1), Vec.new(2, 2)]
mixed[0] = "x"
mixed << 5
puts mixed.length
puts mixed[0]
puts mixed[1].x
puts mixed[2]
