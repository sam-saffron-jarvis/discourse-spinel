# --int-overflow=promote widens every Integer slot after the fixpoint, so a
# producer of an Integer array that reads one -- [x], [x, x * 2], a map --
# is a poly array in the final types. The slots those flow into were decided
# as Integer arrays during the fixpoint; each kind of slot is re-derived
# after the widening (#4738): a multiple assignment's splat and plain
# targets, a global, an ivar (plain, ||=, and a tail write returning a
# method's value), a callee's parameter and a Ruby-defined builtin's
# receiver, a block parameter over the widened array (a slice for
# each_cons), a local pinned to a table's row kind, and an array pushed a
# boxed value. Same answers as the default mode.
def a5(x); *a = x; a; end
p a5(1)
def a6(x); *a, b = x; [a, b]; end
p a6(1)
$seen = [0, 0]
class Ord
  attr_reader :v
  def initialize(v); @v = v; end
  def ==(o); $seen = [v, o.v]; v == o.v; end
end
Ord.new(1) == Ord.new(2)
p $seen
class Box
  def initialize; @n = nil; @calls = 0; end
  def bump; @calls += 1; [@calls]; end
  def set; @n = bump; end
  def composite = @a ||= [bump.first * 10]
end
b = Box.new
p b.set, b.set, b.composite, b.composite
def rows(n) = [[n, n + 1], [n * 2, n * 3]]
t = rows(1)
row = t[1]
p row[1]
p [1, 2, 3, 4].each_cons(2).with_index(1).map { |(x, y), i| [x - y, i] }
v = [1, 2, nil][2]
p [v, 7].filter_map { |x| x }
def sq(a) = a.map { |x| x * x }
p sq([2, 3])
out = []
[5, 6].each { |x| out << x * 2 }
p out
p [2 ** 40, 3].map { |x| x * (2 ** 30) }
