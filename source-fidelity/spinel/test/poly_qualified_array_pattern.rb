# A qualified array pattern (`in Pt[a, b]`) on a value whose class is only
# known at run time. The condition never asked the class, a user class's own
# #deconstruct had no runtime hook (only Data and Struct did), and the
# bindings indexed the object instead of what it deconstructs to: a Pt read
# out of a mixed array matched nothing, and a Struct matched `Pt[a, b]`.
class Pt
  attr_reader :x, :y
  def initialize(x, y) = (@x = x; @y = y)
  def deconstruct = [x, y]
  def deconstruct_keys(keys) = {x: x, y: y}
end
class Other; end
S = Struct.new(:a, :b)
[Pt.new(1, 2), Pt.new(3, 4), S.new(5, 6), Other.new, [7, 8], 5, "s"].each do |v|
  r = case v
      in Pt[1, b] then [:pt1, b]
      in Pt[a, b] then [:pt, a, b]
      in S[a, b] then [:s, a, b]
      in [a, b] then [:arr, a, b]
      in Integer then :int
      else :other
      end
  p r
end
[Pt.new(1, 2), 5].each do |v|
  case v
  in Pt(x:, y:) then p [:ptk, x, y]
  in {x: Integer => x} then p [:hash, x]
  else p :no
  end
end
[[Pt.new(1, 2), 3], 4].each do |v|
  case v
  in [Pt[a, _], c] then p [:nested, a, c]
  else p :no
  end
end
