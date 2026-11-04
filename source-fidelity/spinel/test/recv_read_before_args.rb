# A call reads its receiver before it evaluates its arguments. A global,
# ivar or class variable receiver was read after the argument prelude ran,
# so an argument that reassigns the slot changed the receiver.

def replace
  $a = [2]
  3
end
$a = [1]
p($a + [replace])
$a = [1]
p($a.union([replace]))
$a = [1]
p($a.include?([replace].first))
$a = [1]
b = $a | [replace]
p b
$a = [1]
p [$a, [replace]]
def rs
  $s = "z"
  "b"
end
$s = "a"
p($s + [rs].first)

class Box
  @@c = [1]
  def initialize
    @a = [1]
  end
  def swap
    @a = [9]
    @@c = [9]
    1
  end
  def run
    p(@a + [swap])
    @a = [1]
    p(@a.include?([swap].first))
    @@c = [1, 2]
    p(@@c - [swap])
  end
end
Box.new.run
def g
  $s = "zz"
  "a"
end
$s = "a"
p($s == [g].first)
$x = [1]
def gx
  $x = [7]
  8
end
p($x.push(gx), $x)
$n = 5
def gn
  $n = 100
  1
end
p($n + [gn].first)
