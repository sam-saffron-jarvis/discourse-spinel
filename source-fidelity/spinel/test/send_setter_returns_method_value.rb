# `obj.send(:x=, v)` is a method call, so its value is what the writer
# returns; only the assignment syntax `obj.x = v` evaluates to v (#4921).
class C
  def x=(v)
    @x = v * 2
  end
  attr_accessor :y
end
c = C.new
p c.send(:x=, 5)
p c.public_send(:x=, 6)
p c.__send__("x=", 7)
p(c.x = 8)
p c.send(:y=, 9)
p(c.y = 10)

class D
  def x=(v)
    "d#{v}"
  end
end
[C.new, D.new].each { |o| p o.send(:x=, 3) }
