# An Array op-assign on an ivar, global, class variable or attribute: `|=`
# `&=` `-=` were emitted as the raw C operator between two array pointers,
# and `@a *= 2` widened the ivar to poly, after which `|=` took the integer
# bit operator (#4833).

class Flash
  def initialize = @erasing = [0]
  def erase(offset) = @erasing |= [offset >> 4]
  attr_reader :erasing
end
f = Flash.new
f.erase(0x10)
f.erase(0x12)
p f.erasing

class Box
  attr_accessor :a
  @@c = [1, 2, 3]
  def initialize
    @i = [1, 2, 3]
    @s = %w[a b c]
    @f = [1.5, 2.5]
    @y = [:x, :y]
  end
  def run
    @i |= [4]; p @i
    @i &= [1, 2, 4]; p @i
    @i -= [2]; p @i
    @i += [9]; p @i
    @i *= 2; p @i
    @s |= ["d"]; p @s
    @s -= ["a"]; p @s
    @s *= 2; p @s
    @f |= [3.5]; p @f
    @y &= [:y]; p @y
    @@c |= [4]; p @@c
    @@c -= [1]; p @@c
    @@c *= 2; p @@c
  end
end
Box.new.run

$g = [1, 2]
$g |= [3]; p $g
$g &= [2, 3]; p $g
$g -= [3]; p $g
$g += [7]; p $g
$g *= 3; p $g

a = [1, 2]
a *= 2
p a
b = Box.new
b.a = [1]
b.a |= [2]
p b.a
