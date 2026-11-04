# The poly `<<`, `&`, `|`, `^` and `>>` arms hoist their receiver into a
# rooted temp (#4740), but hoisted it into a statement expression wrapped
# around the call. That holds only while the operand renders as a C
# expression: an operand that hoists statements of its own puts them in front
# of the whole expression, and the receiver is read after them. Under promote
# that is the ordinary case, because boxing an argument spills its writes
# into the pre-statement buffer -- so a receiver its operand reassigns read
# the NEW value, which is the order #4740 set out to fix.
#
# Ruby evaluates the receiver first. Every line below reassigns, inside the
# operand, the slot the receiver was read from; the answer must be built from
# the value the slot held BEFORE it.
class Bits
  attr_reader :v
  def initialize(v) @v = v end
  def <<(o) Bits.new(@v + o) end
  def >>(o) Bits.new(@v - o) end
  def &(o) Bits.new(@v * o) end
  def |(o) Bits.new(@v + o) end
  def ^(o) Bits.new(@v - o) end
end

def mka(n)
  return "s#{n}" if n < 0
  [1, "a", n]
end

def mku(n)
  return "s#{n}" if n < 0
  Bits.new(n)
end

# an array receiver, reassigned by the operand
a = mka(1)
p(a & (a = mka(5); mka(5)))
b = mka(1)
p(b | (b = mka(5); mka(3)))
c = mka(1)
p(c << (c = mka(5); mka(9)))

# a user object, whose own operator the boxed dispatch reaches
u = mku(7)
p((u & (u = mku(1); mka(0); 2)).v)
w = mku(7)
p((w | (w = mku(1); mka(0); 2)).v)
y = mku(7)
p((y ^ (y = mku(1); mka(0); 3)).v)
z = mku(7)
p((z << (z = mku(1); mka(0); 2)).v)
q = mku(7)
p((q >> (q = mku(1); mka(0); 2)).v)

# an ivar receiver, reassigned by the operand
class Holder
  def initialize; @a = mka(1); end
  def go; @a & (@a = mka(9); mka(9)); end
end
p Holder.new.go
