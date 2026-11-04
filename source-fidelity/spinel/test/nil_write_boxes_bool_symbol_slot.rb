# A nil written to an ivar, attr, cvar or gvar whose other writes are all a
# bool or all a Symbol (or a Class, Rational, Complex) boxes the slot: those
# types have no nil of their own. The write passes skipped every nil write,
# so the slot kept the bare type and read its nil back as false (or the zero
# Symbol): `@v.nil?` folded to false and `p @v` printed false (#4884).

class Latch
  def initialize = @value = nil
  def reset = @value = nil
  def set(flag) = @value = flag
  def value = @value.nil? ? "unset" : @value
end
l = Latch.new
p l.value
l.set(false); p l.value
l.set(true); p l.value
l.reset; p l.value

class Mode
  def initialize = @m = :idle
  def clear = @m = nil
  def set(m) = @m = m
  def show = p([@m, @m.nil?, @m ? 1 : 0, @m == nil, @m.inspect, "#{@m}|"])
end
m = Mode.new
m.show; m.clear; m.show; m.set(:run); m.show

class Tri
  def initialize = @state = nil
  def yes = @state = true
  def no = @state = false
  def to_s = @state.nil? ? "?" : (@state ? "Y" : "N")
end
t = Tri.new
puts "#{t}"; t.yes; puts "#{t}"; t.no; puts "#{t}"

class Opt
  attr_accessor :v
  def initialize = @v = false
end
o = Opt.new
p o.v; o.v = nil; p [o.v, o.v.nil?]; o.v = true; p o.v

class Tag
  attr_accessor :t
  def initialize = @t = :a
end
g = Tag.new
g.t = nil; p [g.t, g.t.nil?]; g.t = :b; p g.t

# an attr write through an untyped receiver
class Flagged
  attr_accessor :flag
  def initialize = @flag = true
end
f = [Flagged.new, 1][0]
f.flag = nil
p [f.flag, f.flag.nil?]

class Store
  @@on = nil
  def self.set(x) = @@on = x
  def self.clear = @@on = nil
  def self.show = p([@@on, @@on.nil?])
end
Store.show; Store.set(true); Store.show; Store.clear; Store.show

$sym = :a
def gclear = $sym = nil
p [$sym, $sym.nil?]; gclear; p [$sym, $sym.nil?]

$g = false
$g ||= nil
p [$g, $g.nil?]

module Arm
  def arm = @on = true
  def disarm = @on = nil
  def on_state = @on.nil? ? "unset" : @on
end
class A1
  include Arm
  def initialize = @on = false
end
class B1
  include Arm
  def initialize = @on = false
end
a1 = A1.new; b1 = B1.new
p a1.on_state; a1.disarm; p a1.on_state; a1.arm; p a1.on_state
b1.disarm; p b1.on_state

class Base
  def initialize = @done = false
  def show = p([@done, @done.nil?])
end
class Sub < Base
  def reset = @done = nil
end
sb = Sub.new; sb.show; sb.reset; sb.show

class Chain
  def initialize = @x = @y = nil
  def set = (@x = true; @y = :s)
  def show = p([@x, @y, @x.nil?, @y.nil?])
end
ch = Chain.new; ch.show; ch.set; ch.show

class Viaset
  def initialize = @k = true
  def k = @k
  def clr = instance_variable_set(:@k, nil)
end
vs = Viaset.new; p vs.k; vs.clr; p vs.k

def nothing = nil
class Idle
  def initialize = @s = :idle
  def clear = @s = nothing
  def show = p([@s, @s.nil?])
end
id = Idle.new; id.show; id.clear; id.show

Pt = Struct.new(:flag)
pt = Pt.new(true)
pt.flag = nil
p [pt.flag, pt.flag.nil?]

class Other
  def initialize = @v = nil
  def set(x) = @v = x
  def show = p([@v.nil?, @v])
end
oc = Other.new; oc.show; oc.set(Integer); oc.show
class Rat
  def initialize = @r = nil
  def set(x) = @r = x
  def show = p([@r.nil?, @r])
end
r = Rat.new; r.show; r.set(Rational(1, 3)); r.show

# a bool ivar never written nil stays a plain bool
class Toggle
  def initialize = (@hot = false; @n = 0)
  def tick = (@hot = !@hot; @n += 1 if @hot)
  def n = @n
  def hot = @hot
end
tg = Toggle.new
10.times { tg.tick }
p [tg.n, tg.hot, tg.hot.nil?]

# `@@v ||= x` and `@@v &&= x` as statements on a class variable boxed this
# way test and store the box.
class CvOr
  @@v = nil
  def self.set(x) = @@v = x
  def self.fill
    @@v ||= true
    nil
  end
  def self.clear
    @@v &&= false
    nil
  end
  def self.get = @@v
end
CvOr.fill
p CvOr.get
CvOr.set(true)
CvOr.clear
p CvOr.get
CvOr.set(nil)
CvOr.clear
p CvOr.get
CvOr.fill
p CvOr.get
# ... and `@@v &&= x` as a value answers the unchanged false, not nil.
class CvAndVal
  @@v = nil
  def self.set(x) = @@v = x
  def self.both = (@@v &&= true)
end
CvAndVal.set(false)
p CvAndVal.both
CvAndVal.set(nil)
p CvAndVal.both
CvAndVal.set(true)
p CvAndVal.both
