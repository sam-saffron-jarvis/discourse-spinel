# A leading optional before a required parameter with a **kw: the required
# one is funded first, and a surplus positional raises (poly arm and direct)
class A
  def m(a = {}, b, **kw) = [a, b, kw]
end
class B
  def m(x) = [:b, x]
end
def pick(f) = f ? A.new : B.new
o = pick(true)
p o.m(1, 2)
p o.m(9)
begin
  p o.m(1, 2, 3)
rescue ArgumentError => e
  p e.message
end
p pick(false).m(7)
# a direct call to the same shape
p A.new.m(9)
p A.new.m(1, 2, k: 3)
def top(a = 5, b, **kw) = [a, b, kw]
p top(1)
p top(1, 2)
p top(1, z: 1)
