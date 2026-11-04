# --emit-types carries each node's span, kind and name, and names the widened
# slot in its warnings (#4522); the emit-types leg of infer-test reads this.
class Point
  def initialize(x, y) = (@x = x; @y = y)
  def x = @x
  def dist2(o)
    dx = @x - o.x
    dx * dx
  end
end
def widen(a, b) = a
pts = [Point.new(1, 2), Point.new(3, 4)]
puts pts.map { |p| p.dist2(pts[0]) }.inspect
widen(1, 2)
widen("s", 3)
r = widen(nil, 4)
p r
# keeps `pts` a mixed (poly) array, so line 13 is a class switch whatever
# the object-array narrowing decides (#4846)
pts << 1 if ARGV.size > 99
