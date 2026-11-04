# A constant whose value IS a class, then declared with `class`, is an ordinary
# idiom -- the declaration reopens the value -- and stays legal. It is the
# DISAGREEMENT that #4318 refuses, so this is the side that must keep working.
Point = Struct.new(:x, :y)
class Point
  def dist = x + y
end
p Point.new(1, 2).dist

Rec = Data.define(:a)
class Rec
  def twice = a * 2
end
p Rec.new(a: 3).twice

# Same leaf name in two namespaces is two constants, not one.
module Outer
  module Inner
    C = 7
  end
end
module Holder
  class C
    X = 11
  end
end
p Outer::Inner::C
p Holder::C::X
