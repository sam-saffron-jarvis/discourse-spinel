# An empty `[]` / `{}` pushed into an ivar array is a container element: the
# slot is the poly array. It used to be no evidence at all, so `@c = []` kept
# the int array the empty literal defaults to and the push handed it a
# PolyArray pointer, which did not compile.
class Rows
  def initialize
    @c = []
    @h = []
  end
  def grow
    @c << []
    @c[0] << 1
    @c[0] << 2
    @h << {}
    @h[0]["k"] = 3
  end
  def sum
    r = @c[0]
    r[0] + r[1] + @h[0]["k"]
  end
end
t = Rows.new
t.grow
p t.sum
p t.instance_variables

# A block parameter over a poly-array ivar (or global) is the poly element,
# even when a push inside the block runs ahead of the binding: `r << 1.5`
# used to type r a float array, and the loop then assigned the boxed element
# to it.
class Table
  def initialize
    @a = Array.new(2) { [] }
    @b = [[0.5], [0.5]]
  end
  def go
    @a.each { |r| r << 1.5 }
    @b.each { |r| r << 2.5 }
    p @a
    p @b
  end
end
Table.new.go
$g = [[0.5]]
$g.each { |r| r << 1.5 }
p $g
