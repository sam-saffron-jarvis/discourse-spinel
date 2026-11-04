# An override family whose methods put a rest parameter and a plain one in
# the same position (`A#m(x, y = 2)` under `B#m(x, *rest)`): when the plain
# one is widened to poly by its callers, the rest still collects its
# arguments into an array. The family's type unification widened both to
# poly, slot by slot, so the rest became a boxed value its own packing no
# longer fits, and a direct call or a dispatched one did not compile (#4871).

def t
  yield
rescue ArgumentError
  :argument_error
end

class A
  def m(x, y = 2) = [x, y]
  def run1 = m(3, 4)
  def run2 = m(3, "s")
end

class B < A
  def m(x, *rest) = [x, rest.size]
end

class C < B
end

[A, B, C].each do |k|
  p [k, k.new.m(3, 4), k.new.m(3, "s"), k.new.run1, k.new.run2]
end

class P
  def m(x, *rest) = [x, rest.size]
  def run1 = m(3, 4)
  def run2 = m(3, "s")
end

class Q < P
  def m(x, y = 0) = [x, y]
end

[P, Q].each do |k|
  p [k, k.new.m(3, 4), k.new.m(3, "s"), k.new.run1, k.new.run2]
end

class Later
  def m(x, y, z = 1) = [x, y, z]
  def run1 = m(1, 2, 3)
  def run2 = m(1, 2, "s")
end

class LaterRest < Later
  def m(x, y, *r) = [x, y, r.size]
end

[Later, LaterRest].each do |k|
  p [k, k.new.m(1, 2, 3), k.new.m(1, 2, "s"), k.new.run1, k.new.run2]
end

class Post
  def m(x, y) = [x, y]
  def run = m(3, "s")
end

class PostRest < Post
  def m(*r, y) = [r.size, y]
end

[Post, PostRest].each { |k| p [k, k.new.m(3, 4), k.new.run] }

class Mono
  def m(x, y = 2) = [x, y]
  def run = m(3, 4)
end

class MonoRest < Mono
  def m(x, *rest) = [x, rest.size]
end

[Mono, MonoRest].each { |k| p [k, k.new.run, t { k.new.m(1) }] }

class Plain
  def m(x, y = 2) = [x, y]
  def run1 = m(3, 4)
  def run2 = m(3, "s")
end

class PlainChild < Plain
  def m(x, y) = [x, y.class]
end

[Plain, PlainChild].each { |k| p [k, k.new.run1, k.new.run2] }
