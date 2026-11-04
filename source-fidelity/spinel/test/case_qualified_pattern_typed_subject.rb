# `in Sub(x:)` / `in Sub[a, b]` on a subject typed as a user class asks the
# class first, as CRuby tests `Sub === obj` before it deconstructs. The
# qualifier was dropped on this path, so a Shape matched `in Sub(x:)`
# whenever its fields did.
class Shape
  attr_reader :x
  def initialize(x) = @x = x
  def deconstruct_keys(k) = {x: @x}
  def deconstruct = [@x, 0]
end
class Sub < Shape
  def deconstruct_keys(k) = {x: @x * 10}
end
class Other; end

u = Shape.new(1)
p(case u; in Sub(x:) then :sub; else :else; end)
p(case u; in Sub[a, b] then :sub; else :else; end)
p(case u; in Shape(x:) then x; else :else; end)

s = Sub.new(3)
p(case s; in Shape(x:) then x; else :else; end)
p(case s; in Sub(x:) then x; else :else; end)
p(case s; in Other(x:) then x; else :else; end)

def maybe(f) = f ? Shape.new(4) : nil
n = maybe(false)
p(case n; in Shape(x:) then x; in nil then :nil; else :else; end)

Point = Struct.new(:px, :py)
class P3 < Point; end
pt = Point.new(1, 2)
p(case pt; in P3[a, b] then :p3; in Point[a, b] then [a, b]; else :else; end)
p(case pt; in P3(px:) then :p3; in Point(px:) then px; else :else; end)
