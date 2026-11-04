# a default reading an earlier parameter, in a method with *rest or **kwrest
def m(n, *r, k: n + r.size) = k
p m(3, 1, 2)
p m(3)
p m(3, 1, k: 0)
def h(x, y = 7, z = x * 2, **kw) = [x, y, z, kw]
p h(1, j: 2)
p h(1, 2, 3)
p h(1)
def g(a, b = a + 1, *rest, c) = [a, b, rest, c]
p g(1, 9)
p g(1, 2, 9)
p g(1, 2, 3, 4, 9)
def s(a, *r, t: r.sum + a, **o) = [a, r, t, o]
p s(1, 2, 3)
p s(1, 2, t: 0, u: 5)
class O
  def m(n, *r, k: n + r.size) = k
  def h(x, y = 7, z = x * 2, **kw) = [x, y, z, kw]
end
o = O.new
p o.m(3, 1, 2)
p o.m(3, k: 1)
p o.h(1, j: 2)
p o.h(2, 3)
# the same through a poly receiver
class Q
  def m(n, *r, k: n + r.size) = k
  def h(x, z = x * 2, **kw) = [x, z, kw]
  def g(a, b = 1, *r, k: 0) = [a, b, r, k]
end
class R
  def m(n, *r, k: n + r.size) = k + 100
  def h(x, z = x * 3, **kw) = [x, z, kw]
  def g(a, b = 2, *r, k: 0) = [a, b, r, k]
end
[Q.new, R.new].each do |q|
  p q.m(3, 1, 2)
  p q.m(3)
  p q.m(3, k: 1)
  p q.h(1)
  p q.h(1, 5, j: 2)
  p q.g(1, 7, 8)
  p q.g(1)
end
# a poly receiver's **kwrest with no keywords passed is empty
class S
  def h(x, **kw) = [x, kw]
end
class U
  def h(x, **kw) = [x, kw, 1]
end
[S.new, U.new].each { |q| p q.h(1); p q.h(1, a: 2) }
# caller locals sharing a parameter's name are the caller's
class V
  def m(n, *r, k: n + r.size) = [n, r, k]
  def h(x, z = x * 2, **kw) = [x, z, kw]
end
def m2(n, *r, k: n + r.size) = [n, r, k]
def h2(x, z = x * 2, **kw) = [x, z, kw]
n = 10
r = 20
x = 30
kw = 40
o = V.new
p o.m(1, n, r)
p m2(1, n, r)
p o.h(1, j: x, q: kw)
p h2(1, j: x, q: kw)
