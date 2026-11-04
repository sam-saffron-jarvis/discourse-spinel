# A class defining `round(digits)` took over the name's dispatch, and the
# Integer or Float in the same poly slot had no arm: `round(1)` on a poly
# Integer|Float receiver raised NoMethodError. The zero-arg forms had their
# numeric default; the precision forms round(n) / ceil(n) / floor(n) /
# truncate(n) now do too, and ceil/floor/truncate with a precision on a poly
# receiver had no arm even without a user class (#4532, elektronaut).
class V
  attr_reader :x
  def initialize(x) = @x = x
  def round(digits)
    x.round(digits)
  end
  def ceil(digits) = x.ceil(digits)
end
p V.new(2.4).round(1)
p V.new(2).round(1)
p 2.45.round(1)
p V.new(2.45).ceil(1)
p V.new(1234).ceil(-2)
nums = [2.456, 1234, -2.456]
nums.each do |v|
  p [v.round(2), v.ceil(2), v.floor(2), v.truncate(2), v.round(-2), v.ceil(-2), v.floor(-2), v.truncate(-2)]
end
n = 1
p nums.map { |v| v.round(n) }
p nums.map { |v| v.floor(n) }
p [V.new(9.87), V.new(10)].map { |o| o.round(1) }
mixed = [V.new(9.87), 3.14159, 42]
p mixed.map { |o| o.round(1) }
