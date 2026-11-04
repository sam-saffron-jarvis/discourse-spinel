# `x |= v` (and `&=` `-=` `+=` `*=`) on an array slot reads x before it
# evaluates v, so an rhs that reassigns the slot still operates on the old
# array. An array-literal rhs is built ahead of the op-assign line, and the
# operation read the slot after that build, taking the NEW value -- on a
# local, an ivar, a global, a class variable and an attribute, in statement
# and value position (#4875).

def rep
  $a = [2]
  3
end

$a = [1]
$a |= [rep]
p $a
$a = [1, 3]
$a &= [rep, 1]
p $a
$a = [1, 3]
$a -= [rep]
p $a
$a = [1]
$a += [rep]
p $a
$a = [1]
$a *= [rep].first - 1
p $a
$a = [1]
x = ($a |= [rep])
p x
$a = [1]
$a |= (rep; [4])
p $a

def local_ops
  a = [1, 5]
  a |= [(a = [2, 5]; 1), 5]
  b = [1, 5]
  b &= [(b = [2, 5]; 1), 5]
  c = [1, 5]
  c -= [(c = [2, 5]; 1)]
  d = [1]
  f = proc { d = [9]; 4 }
  d += [f.call]
  e = [1]
  v = (e |= [(e = [2]; 3)])
  [a, b, c, d, v]
end
p local_ops

class Holder
  def initialize
    @a = [1]
    @s = ["x"]
  end

  def bump
    @a = [2]
    @s = [:z.to_s]
    3
  end

  def ops
    @a |= [bump]
    r = [@a]
    @a = [1]
    @a += [bump]
    r << @a
    @a = [1]
    r << (@a -= [bump, 1])
    @s = ["x"]
    @s |= [bump.to_s]
    r << @s
    r
  end
end
p Holder.new.ops

class Reg
  @@a = [1]

  def self.bump
    @@a = [2]
    3
  end

  def self.ops
    @@a |= [bump]
    r = [@@a]
    @@a = [1]
    @@a += [bump]
    r << @@a
    @@a = [1]
    r << (@@a &= [bump, 1])
    r
  end
end
p Reg.ops

$p = [1, "x"]
def pb
  $p = [:z]
  "y"
end
$p |= [pb, 2]
p $p

class Box
  attr_accessor :items
  def initialize; @items = [1]; end
end
$box = Box.new
$order = []
def box_bump
  $order << :rhs
  $box.items = [2]
  3
end
def pick
  $order << :recv
  $box
end
pick.items |= [box_bump]
p $box.items
p $order
$box.items = [1]
$box.items += [box_bump]
p $box.items

def grow
  $g = [$g.size * 10]
  $g.size
end
$g = [1]
p([1, 2, 3].map { $g |= [grow, 7] })
$g = [1]
3.times { |k| $g -= [grow + k] }
p $g

# An rhs with no prelude -- a plain method call that reassigns the slot --
# is still evaluated after the slot is read.
def op_make_arr
  $opm = [2]
  [3]
end
$opm = [1]
$opm |= op_make_arr
p $opm
class OpM
  @@x = [1]
  def self.mk
    @@x = [7]
    [3]
  end
  def self.go = (@@x += mk)
end
p OpM.go
@ivm = [1]
def ivm_mk
  @ivm = [7]
  [3]
end
@ivm -= ivm_mk
p @ivm
