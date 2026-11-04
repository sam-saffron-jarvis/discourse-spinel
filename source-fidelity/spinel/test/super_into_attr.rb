# A `super` from a method overriding attr_reader / attr_writer /
# attr_accessor, or a Struct / Data member, calls the generated accessor:
# it reads or writes the backing ivar. The super found no method in the
# parent chain and raised NoMethodError.

class WBase
  attr_writer :clock
  def clock_value = @clock
end

class WBare < WBase
  def clock=(clock)
    super
    @seen = true
  end
  def seen = @seen
end

class WExplicit < WBase
  def clock=(clock)
    super(clock * 2)
  end
end

w = WBare.new
w.clock = 5
p w.clock_value, w.seen
r = (w.clock = 6)
p r, w.clock_value
e = WExplicit.new
e.clock = 5
p e.clock_value

class ABase
  attr_accessor :clock
end

class ABoth < ABase
  def clock = super * 10
  def clock=(v)
    x = super(v + 1)
    @ret = x
  end
  def ret = @ret
end

a = ABoth.new
a.clock = 4
p a.clock, a.ret

class RBase
  attr_reader :count
  def initialize = @count = 5
end

class RBare < RBase
  def count = super + 1
end

class RParen < RBase
  def count = super() + 2
end

p RBare.new.count, RParen.new.count

class RNilBase
  attr_reader :label
end

class RNil < RNilBase
  def label
    v = super
    v.nil? ? :none : v
  end
end

p RNil.new.label

# two levels up, and past an override in the middle
class Grand
  attr_accessor :level
end

class Middle < Grand
end

class Leaf < Middle
  def level=(v)
    super
    @hit = true
  end
  def level = super.to_s
  def hit = @hit
end

l = Leaf.new
l.level = 5
p l.level, l.hit

class Doubler < Grand
  def level=(v)
    super(v * 2)
  end
end

class Plus < Doubler
  def level=(v)
    super(v + 1)
  end
end

pl = Plus.new
pl.level = 5
p pl.level

# an attribute redeclared below a method answers the super, not the method
class MethodGrand
  def pos=(v)
    @pos = -v
  end
  def pos = @pos
end

class AttrParent < MethodGrand
  attr_writer :pos
end

class AttrChild < AttrParent
  def pos=(v)
    super
  end
end

ac = AttrChild.new
ac.pos = 5
p ac.pos

# the value is typed by what the super writes
class Named
  attr_accessor :name, :rate, :items
end

class Upper < Named
  def name=(n)
    super(n.upcase)
  end
  def rate=(r)
    super(r.to_f)
  end
  def items=(a)
    super(a.map { |x| x * 2 })
  end
end

u = Upper.new
u.name = "abc"
u.rate = 3
u.items = [1, 2]
p u.name, u.name.size, u.rate / 2, u.items.sum

class Slot
  attr_accessor :value
end

class AnySlot < Slot
  def value=(v)
    super
  end
end

s = AnySlot.new
s.value = 5
p s.value
s.value = "x"
p s.value

class Cart
  def initialize(n) = @n = n
  def name = "cart#{@n}"
end

class Bus
  attr_accessor :cartridge
  def describe = @cartridge ? @cartridge.name : "none"
end

class C64Bus < Bus
  def cartridge=(cart)
    super
    @remapped = true
  end
  def remapped = @remapped
end

bus = C64Bus.new
p bus.describe
bus.cartridge = Cart.new(1)
p bus.describe, bus.remapped
bus.cartridge = nil
p bus.describe

[Slot.new, AnySlot.new].each do |o|
  o.value = 2
  p o.value
end

# attributes from an included module
module Clocked
  attr_accessor :tick
end

class ModBase
  include Clocked
end

class ModChild < ModBase
  def tick=(v)
    super
    @seen = true
  end
  def seen = @seen
end

class ModDirect
  include Clocked
  def tick=(v)
    super(v + 1)
  end
end

mc = ModChild.new
mc.tick = 5
md = ModDirect.new
md.tick = 5
p mc.tick, mc.seen, md.tick

module Hook
  def tick=(v)
    super(v + 1)
  end
end

class Hooked < ModBase
  include Hook
end

h = Hooked.new
h.tick = 1
p h.tick

# Struct and Data members
S = Struct.new(:clock)

class SChild < S
  def clock=(v)
    super
    @seen = true
  end
  def clock = super * 2
  def seen = @seen
end

sc = SChild.new(1)
p sc.clock
sc.clock = 5
p sc.clock, sc.seen

D = Data.define(:x)

class DChild < D
  def x = super * 2
end

p DChild.new(x: 4).x

# forwarding shapes
class Shapes < ABase
  def clock=(v = 9)
    v = v * 2
    [1].each { super }
  end
end

sh = Shapes.new
sh.clock = 3
p sh.clock

# a singleton method's super
SOLO = ABase.new
def SOLO.clock=(v)
  super(v + 100)
end
SOLO.clock = 1
p SOLO.clock

# an attribute on the same class is overridden, not reached by super
class SameClass
  attr_accessor :x
  def x = super
end

begin
  SameClass.new.x
rescue NoMethodError
  puts "NoMethodError"
end

# the write still raises on a frozen receiver
fz = WBare.new
fz.clock = 1
fz.freeze
begin
  fz.clock = 2
rescue FrozenError => err
  p err.class
end
p fz.clock_value
