# `|=` `&=` `-=` `+=` `*=` on an array held in a global or a class variable,
# used as a value -- a method's last expression, a block's, an assignment's
# right-hand side -- yield the updated array. The value arm emitted the raw
# C operator between two array pointers, which did not compile; #4833 fixed
# the statement form only.

$a = [0, 1, 2]
$s = ["a"]

def g_or(x) = $a |= [x, 5]
def g_and = $a &= [0, 1, 5]
def g_minus(x) = $a -= [x]
def g_plus = $a += [7]
def g_times(n) = $a *= n
def g_strs = $s |= ["b", "a"]

class C
  @@a = [0, 1, 2]
  @@f = [1.5]
  @@e = [3]

  def u_or(x) = @@a |= [x, 5]
  def u_and = @@a &= [0, 1, 5]
  def u_minus(x) = @@a -= [x]
  def u_plus = @@a += [7]
  def self.times(n) = @@a *= n
  def self.floats = @@f |= [2.5, 1.5]
  def self.empty = @@e += []
  def self.cleared = @@e &= []
  def self.chain = (@@a -= [7]).size

  def in_block(x) = [1, 2].map { @@a |= [x] }

  def assigned(x)
    y = (@@a -= [x])
    y.size
  end

  def a = @@a
end

p g_or(1)
p g_or(9)
p g_and
p g_minus(5)
p g_plus
p g_times(2)
p $a
p g_strs
p [10].map { $s += ["c"] }
y = ($a -= [7])
p y
p $s

c = C.new
p c.u_or(1)
p c.u_or(9)
p c.u_and
p c.u_minus(5)
p c.u_plus
p C.times(2)
p C.floats
p C.empty
p C.cleared
p C.chain
p c.in_block(4)
p c.assigned(4)
p c.a
