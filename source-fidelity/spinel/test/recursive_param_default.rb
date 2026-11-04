# A parameter default that calls its own method with that argument omitted
# again, directly or through another method's default, is evaluated once per
# call as CRuby does. Filling it in place at the call site never terminated,
# and the compiler ran out of stack (#4900).

def m(x, y = (x > 0 ? m(x - 1)[0] : 0)) = [x, y]
p m(3)
p m(0)
p m(2, 9)

def f(n, a = (n > 0 ? g(n - 1) : 100)) = n + a
def g(n, b = (n > 0 ? f(n - 1) : 200)) = n * 2 + b
p f(3)
p g(3)
p f(1, 5)

def a3(n, v = (n > 0 ? b3(n - 1) : 0)) = v + 1
def b3(n, v = (n > 0 ? c3(n - 1) : 0)) = v + 10
def c3(n, v = (n > 0 ? a3(n - 1) : 0)) = v + 100
p a3(5)
p c3(2)

class R
  def m(x, y = (x > 0 ? m(x - 1)[0] : 0)) = [x, y]
  def s(x, y = (x > 0 ? self.s(x - 1) + 1 : 0)) = y
end
p R.new.m(3)
p R.new.m(4, 1)
p R.new.s(5)

class K
  def self.depth(n, acc = (n > 0 ? depth(n - 1) + 1 : 0))
    acc
  end
end
p K.depth(4)
p K.depth(2, 7)

module Mo
  def self.f(n, a = (n > 0 ? f(n - 1) + 1 : 0)) = a * 2
end
p Mo.f(3)

class Node
  attr_reader :n, :child
  def initialize(n, child = (n > 0 ? Node.new(n - 1) : nil))
    @n = n
    @child = child
  end
  def size = 1 + (child ? child.size : 0)
end
p Node.new(3).size
p Node.new(2).child.n
p Node.new(1, nil).size

# every argument supplied: nothing to recurse into
def full(x, y = (x < 3 ? full(x + 1, 10) * 2 : 0)) = x + y
p full(1)
p full(1, 2)

# reading earlier parameters, and a local of its own
def e(x, y = x * 2, z = (x > 0 ? e(x - 1)[2] + y : y)) = [x, y, z]
p e(3)
p e(2, 1)
p e(1, 1, 1)
def t(n, v = (w = n * 2; n > 0 ? t(n - 1) + w : w)) = v
p t(3)
def two(n, a = (n > 0 ? two(n - 1)[1] : 1), b = (n > 0 ? two(n - 1)[0] + a : 2)) = [a, b]
p two(3)
p two(3, 5)

class Q
  def a(n, v = (n > 0 ? b(n - 1) : "a0")) = "a(#{v})"
  def b(n, v = (n > 0 ? a(n - 1) : "b0")) = "b(#{v})"
end
p Q.new.a(3)
p Q.new.b(2)

def str(n, pre = (n > 0 ? str(n - 1) + "-" : "")) = pre + n.to_s
p str(4)
p str(2, "x")

def kw(n, acc: (n > 0 ? kw(n - 1) + n : 0)) = acc
p kw(4)
p kw(4, acc: 1)

def blk(x, y = (x > 0 ? [blk(x - 1)].map { |v| v + 1 }.first : 0)) = y
p blk(3)

def fl(n, acc = (n > 0 ? fl(n - 1) * 1.5 : 1.0)) = acc
p fl(3)

class I
  def initialize(k) = @k = k
  def m(n, v = (n > 0 ? m(n - 1) + @k : @k)) = v
end
p I.new(3).m(4)
p I.new(2).m(1, 100)

class P
  def go = m(3)
  private def m(x, y = (x > 0 ? m(x - 1) + 1 : 0)) = y
end
p P.new.go

class A
  def m(x, y = (x > 0 ? m(x - 1) : 0)) = y + 1
end
class B < A
  def m(x, y = 50) = x > 1 ? super(x, y) : y
end
p A.new.m(3)
p B.new.m(3)

class Z
  def m(x, y = (x > 0 ? n(x - 1) + 1 : 0)) = y
  alias n m
end
p Z.new.m(3)

p R.instance_methods(false).sort
p R.private_instance_methods(false)
p R.new.respond_to?(:m)

# a method the program names like a helper is still its own, and visible
class U
  def __sp_default_x = :mine
  def m(x, y = (x > 0 ? m(x - 1) + 1 : 0)) = y
end
p U.new.m(2)
p U.new.__sp_default_x
p U.new.respond_to?(:__sp_default_x)
p U.instance_methods(false).sort
