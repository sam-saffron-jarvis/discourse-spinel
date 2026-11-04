# A class constructed only inside a method nothing calls mints no instance,
# so it gets no arm of a poly receiver's dispatch, and a dispatch whose only
# real arm is a field read must not root its receiver for the arm it does
# not carry: the read `d.x` below paid a root push and pop per iteration for
# Vec#x, a method no value can ever reach (#4460; there the dead class was an
# FFI binding whose float return also widened the read, which is kept out of
# the inferred union for native classes).
class Vec
  def x; @x; end
  def initialize(x); @x = x; end
end
class Dot
  attr_accessor :x, :dx
  def initialize(x, dx); @x = x; @dx = dx; end
end
Cell = Struct.new(:dots)
module Dead
  def self.unused_wrapper
    Vec.new(2)
  end
end
def step(cell)
  ds = cell.dots
  i = 0
  while i < ds.length
    d = ds[i]
    d.x = d.x + d.dx
    i += 1
  end
end
cell = Cell.new([])
cell.dots << Dot.new(1, 2) << Dot.new(5, -1)
3.times { step(cell) }
p cell.dots.map(&:x)
