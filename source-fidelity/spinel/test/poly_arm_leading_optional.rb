# A poly dispatch arm for a method with a leading optional parameter
# (`def h(a = {}, c)`). nrequired is the index past the last required
# parameter (2 here), so `o.h(5)` looked one argument short, every arm was
# dropped, and the call raised NoMethodError.
class A
  def h(a = {}, c) = [:A, a, c]
  def g(a, b = 1, c = 2, d) = [:A, a, b, c, d]
end
class B
  def h(a = {}, c) = [:B, a, c]
  def g(a, b = 1, c = 2, d) = [:B, a, b, c, d]
end
[A.new, B.new].each { |o| p o.h(5) }
[A.new, B.new].each { |o| p o.h(1, 5) }
[A.new, B.new].each { |o| p o.g(7, 8) }
[A.new, B.new].each { |o| p o.g(7, 8, 9) }
