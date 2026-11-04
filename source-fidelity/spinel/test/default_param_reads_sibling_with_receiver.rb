# A parameter default that reads an earlier parameter is evaluated in the
# callee, where that parameter is bound. spinel fills defaults at the call
# site; the bare-call path already binds the parameters to temps first, but
# a call with a receiver (direct or through the poly dispatch) emitted the
# callee's `lv_u` at the call site: undeclared, or a caller local of the
# same name (the `u` below). (#4431)
class K
  def initialize(n)
    @n = n
  end

  def g(u, v = u.upcase)
    u + v
  end

  def h(a, b = a * @n, c = b + 1)
    [a, b, c]
  end

  def self.cm(x, y = x * 3)
    x + y
  end

  def app(s, t = s.length)
    s << "!"
    t
  end

  def kw(a, b: a * 2)
    a + b
  end
end

class L < K
  def g(u, v = u.downcase)
    v + u
  end
end

k = K.new(2)
p k.g("a")
u = "Zz"
p k.g(u)
p k.g(u, "y")
p k.h(5)
p k.h(5, 1)
p K.cm(4)
s = String.new("hi")
p k.app(s)
p s
p k.kw(3)
p k.kw(3, b: 1)
[K.new(1), L.new(1)].each { |o| p o.g("Mx") }
