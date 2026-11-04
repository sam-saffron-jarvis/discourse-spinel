# A template method on a base class calling a hook with arguments that only
# the subclasses define (#4514): the dispatch has no base parameter list to
# read, and the compiler crashed on it. The argument is the call's expression
# and every subclass arm takes it.
class Base
  def go(n) = leaf(n)
  def go2(a, b) = leaf2(a, b)
  def go3 = leaf3
end
class C1 < Base
  def leaf(t) = t * 2
  def leaf2(a, b) = "#{a}-#{b}"
  def leaf3 = :c1
end
class C2 < Base
  def leaf(t) = t + 100
  def leaf2(a, b) = "#{b}-#{a}"
  def leaf3 = :c2
end
[C1.new, C2.new].each do |o|
  puts o.go(4)
  puts o.go2("x", "y")
  p o.go3
end
