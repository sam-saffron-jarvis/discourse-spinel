# `x OP= v` on an Integer, Float or Bignum global, class variable or ivar
# reads x before it evaluates v, so a method in v that reassigns the slot
# does not change the result. A global and a class variable emitted the raw
# C operator (`gv_i += bump()`), which read the slot after the call; the same
# raw operator skipped the overflow check (see int_overflow_op_assign.rb),
# and `**=` did not compile. The ivar's bitwise and Float forms had the raw
# operator too (#4886).

def bump_g
  $i = 100
  3
end

$i = 10
$i += bump_g
p $i
$i = 10
$i -= bump_g
p $i
$i = 10
$i *= bump_g
p $i
$i = 10
$i /= bump_g
p $i
$i = 10
$i %= bump_g
p $i
$i = 10
$i **= bump_g
p $i
$i = 10
$i <<= bump_g
p $i
$i = 10
$i |= bump_g
p $i
$i = 10
p($i += bump_g)
$i = 10
p($i **= bump_g)
$i = 0
[1, 2, 3].each { |x| $i += (bump_g - 3 + x) }
p $i

def bump_f
  $f = 100.0
  2.25
end
$f = 1.5
$f += bump_f
p $f
$f = 1.5
p($f *= bump_f)

def bump_b
  $b = 0
  3
end
$b = 2**64
$b += bump_b
p $b

class C
  @@i = 10
  @@f = 1.5

  def self.bump
    @@i = 100
    3
  end

  def self.bump_f
    @@f = 100.0
    2.25
  end

  def self.go
    @@i += bump
    p @@i
    @@i = 10
    @@i -= bump
    p @@i
    @@i = 10
    @@i *= bump
    p @@i
    @@i = 10
    @@i **= bump
    p @@i
    @@i = 10
    @@i <<= bump
    p @@i
    @@i = 10
    @@i ^= bump
    p @@i
    @@i = 10
    p(@@i += bump)
    @@i = 10
    p(@@i /= bump)
    @@f += bump_f
    p @@f
    @@f = 1.5
    p(@@f -= bump_f)
  end
end
C.go

class D
  def initialize
    @i = 10
    @f = 1.5
  end

  def bump
    @i = 100
    3
  end

  def bump_f
    @f = 100.0
    2.25
  end

  def go
    @i += bump
    p @i
    @i = 10
    @i |= bump
    p @i
    @i = 10
    @i <<= bump
    p @i
    @i = 10
    p(@i &= bump)
    @f += bump_f
    p @f
    @f = 1.5
    p(@f /= bump_f)
  end
end
D.new.go
