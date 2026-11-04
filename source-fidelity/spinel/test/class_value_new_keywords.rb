# `k.new(...)` on a class known only at run time, with keyword arguments:
# the keyword hash was counted as one more positional, no class matched,
# and the call raised NoMethodError (#4845).

class A
  def initialize(x) = @x = x
  def x = @x
end
class B < A; end
class K < A
  def initialize(x, boost: 0) = @x = x + boost
end
class R < A
  def initialize(x, scale:) = @x = x * scale
end
TYPES = { 0 => A, 1 => B, 2 => K, 3 => R }.freeze
def build(t) = TYPES.fetch(t).new(5)
def buildk(t) = TYPES.fetch(t).new(5, boost: 3)
def buildkw(t, **kw) = TYPES.fetch(t).new(5, **kw)
p build(0).x
p build(2).x
p buildk(2).x
p buildkw(2, boost: 10).x
p buildkw(3, scale: 3).x
p buildkw(2).x
begin
  buildk(0)
rescue ArgumentError, NoMethodError => e
  p e.class
end
def build_anon(t, **) = TYPES.fetch(t).new(5, **)
p build_anon(2, boost: 4).x
kk = TYPES.fetch(2)
p kk.new(5, **{}).x
