# A module defining to_s or inspect, included into a class, got an arm of its
# own in the boxed to_s / inspect switches, naming sp_M_to_s -- a function no
# TU defines, since a module method is emitted only as its includer's -- so
# the program did not link (#4533, elektronaut).
module M
  def to_s
    "hi"
  end
end
module I
  def inspect
    "#<I-ish #{name}>"
  end
end
class V
  include M
end
class W
  include I
  attr_reader :name
  def initialize(n) = @name = n
end
puts V.new.to_s
puts "#{V.new}"
p [V.new].map(&:to_s)
w = W.new("w1")
p w
p [w]
puts w.inspect
h = { k: V.new }
puts h[:k].to_s
puts w.to_s.start_with?("#<W")
