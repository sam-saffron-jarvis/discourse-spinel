# A program that assigns its own constants named Kernel and BasicObject (to
# modules Shape does not include): a user-class instance matches neither
# name, in `in` or in `when`, and still matches Object. On ec604b80 the
# first three lines already print what the .expected holds; the last prints
# the no-match answer (other).
class Shape; end
$VERBOSE = nil   # reassigning Kernel warns
Kernel = Comparable

module Walls
  BasicObject = Enumerable
  def self.basic(v) = (case v; in BasicObject then "basic"; else "other"; end)
end

s = Shape.new
puts(case s; in Kernel then "kernel"; else "other"; end)
puts(case s; when Kernel then "when kernel"; else "when other"; end)
puts Walls.basic(s)
puts(case s; in Object then "object"; else "other"; end)
