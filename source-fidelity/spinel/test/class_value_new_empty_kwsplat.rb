# An empty `**` forwarded to k.new(...) on a class value reaches an
# initialize that takes no keywords; a non-empty one is ArgumentError (#4849).

class A
  def initialize(x) = @x = x
  def x = @x
end
class B < A; end
class J < A
  def initialize(x, jumper: false)
    super(x)
    @j = jumper
  end
  def j = @j
end
TYPES = { 0 => A, 1 => B, 2 => J }.freeze
def build(t, **) = TYPES.fetch(t).new(5, **)
def buildkw(t, **kw) = TYPES.fetch(t).new(5, **kw)
p build(1).x
p buildkw(1).x
p TYPES.fetch(1).new(5, **{}).x
p build(0).x
p build(2, jumper: true).j
begin
  build(1, z: 1)
rescue ArgumentError => e
  p e.message
end
