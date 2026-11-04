# The poly `==`, `!=` and `<=>` arms passed both operands to one C call,
# which leaves them unsequenced, and hoisted the receiver only when BOTH
# operands contained a call. Neither half held up. Whether the RECEIVER has a
# call of its own says nothing about whether the argument can overwrite it --
# a bare local read is precisely the receiver an argument writes -- and the
# statement expression the hoist used sits inside the expression, so an
# argument that hoists statements of its own (the ordinary case under
# promote, where boxing spills writes into the pre-statement buffer) still
# ran first.
#
# Ruby reads the receiver before the argument. Each line below reassigns,
# inside the argument, the slot the receiver came from.
def mka(n)
  return "s#{n}" if n < 0
  [1, "a", n]
end

b = mka(1)
p(b == (b = mka(5); mka(5)))
c = mka(1)
p(c != (c = mka(5); mka(5)))
e = mka(1)
p(e <=> (e = mka(5); mka(5)))
g = mka(1)
p(g == (g = mka(1); mka(1)))

class Holder
  def initialize; @a = mka(1); end
  def eq;  @a == (@a = mka(5); mka(5)); end
  def cmp; @a <=> (@a = mka(5); mka(5)); end
end
p Holder.new.eq
p Holder.new.cmp

# the receiver is evaluated first, and exactly once
$log = []
def side(n); $log << n; mka(n); end
def arg(n);  $log << "arg#{n}"; mka(n); end
p(side(1) == arg(1))
p $log

# hoisting the receiver must not lift it out of a branch that never runs
$log = []
p(false && (side(2) == arg(2)))
p $log
$log = []
p(false ? (side(3) == arg(3)) : :skipped)
p $log

# `yield` and `super` run Ruby just as a call does, and the block or the
# ancestor method can write the slot the receiver was read from. The operand
# test recognised only a CallNode, so these two stayed unsequenced.
class Y
  attr_accessor :a
  def initialize(v); @a = v; end
  def eq;  @a == yield; end
  def cmp; @a <=> yield; end
end
y = Y.new(mka(1))
p(y.eq { y.a = mka(5); mka(5) })
z = Y.new(mka(1))
p(z.cmp { z.a = mka(5); mka(5) })

class Base
  attr_accessor :a
  def initialize(v); @a = v; end
  def eq;  @a = mka(5); mka(5); end
  def cmp; @a = mka(5); mka(5); end
end
class Kid < Base
  def eq;  @a == super; end
  def cmp; @a <=> super; end
end
p Kid.new(mka(1)).eq
p Kid.new(mka(1)).cmp
