# A poly receiver's dispatch arm whose method refuses the call's argument
# count raises ArgumentError, as CRuby does. The arm used to be kept with
# the extra arguments silently cut off (B#m below answered 4), or dropped,
# so a shortfall answered NoMethodError.
class A
  def m(x, y = 2) = x * y
  def n(x, y) = x + y
  def r(x, *rest) = [x, rest.size]
end
class B < A
  def m(x) = x + 1
  def n(x) = x
  def r(x, y) = [x, y]
end
[A.new, B.new].each do |o|
  begin
    p o.m(3, 4)
  rescue ArgumentError => e
    p e.message
  end
  begin
    p o.n(5)
  rescue ArgumentError => e
    p e.message
  end
  begin
    p o.r(1, 2, 3)
  rescue ArgumentError => e
    p e.message
  end
end
