# `||=` with a composite right-hand side (#4513): a hash or array literal, a
# block-taking call, anything whose codegen needs statements ahead of the
# assignment, ran on every evaluation; the guard held the memo but the work
# was redone, and a right-hand side that raises on its second call raised
# where CRuby answers the memo. The setup now runs inside the guard, in the
# ivar, attribute and local forms, as an expression and as a statement.
$built = 0
class Thing
  def initialize = $built += 1
end
class Box
  def map = @map ||= { 0 => Thing.new, 1 => Thing.new }
  def arr = @arr ||= [Thing.new]
  def blk = @blk ||= Array.new(1) { Thing.new }
  def mapped = @mapped ||= [1].map { Thing.new }
  def one = @one ||= Thing.new
  def str = @str ||= "x#{Thing.new}"
  def count
    @count ||= [1, 2].map { |x| x * 2 }.sum
  end
  def go
    3.times { map; arr; blk; mapped; one; str; count }
    [map.size, arr.size, blk.size, mapped.size, str.size > 0, count]
  end
end
p Box.new.go
p $built

$calls = 0
def risky
  $calls += 1
  raise "second call!" if $calls > 1
  42
end
class Box2
  def composite = @a ||= [risky]
end
box = Box2.new
p box.composite
p box.composite
p $calls

# statement form, and a local
class Box3
  def initialize
    @t = nil
  end
  def fill
    @t ||= { a: Thing.new }
    nil
  end
  def t = @t
end
b3 = Box3.new
before = $built
3.times { b3.fill }
p $built - before
def loc
  memo = nil
  r = []
  3.times do
    memo ||= [Thing.new]
    r << memo.size
  end
  r
end
before = $built
p loc
p $built - before


class Reg
  attr_accessor :cache
  def get = (self.cache ||= { 1 => Thing.new })
  def self.table = @table ||= [Thing.new, Thing.new]
end
r = Reg.new
3.times { r.get }
3.times { Reg.table }
p $built
def local_expr
  h = nil
  vals = 3.times.map { (h ||= { k: Thing.new }).size }
  vals
end
before = $built
p local_expr
p $built - before
x = nil
3.times { x ||= [Thing.new].map { |t| t } }
p $built - before

