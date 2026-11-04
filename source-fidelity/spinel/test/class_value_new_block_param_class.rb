# `k.new(...)` on a class value: an arm for a class whose initialize takes
# `&block` left the block slot out, so the C did not compile (#4855).

class Hook
  def initialize(x, &handler)
    @x = x
    @handler = handler
  end
  def fire = @handler ? @handler.call(@x) : :none
end
class Cb
  def initialize(&b) = @b = b
  def has = !@b.nil?
end
class A
  def initialize(x) = @x = x
  def x = @x
end
class B < A; end
TYPES = { 0 => A, 1 => B, 2 => Hook }.freeze
def build(t) = TYPES.fetch(t).new(5)
Hook.new(1) { |v| p v }.fire
p build(1).x
p build(2).fire
Cb.new { 1 }
k = [Cb, 1][0]
p k.new.has
kk = [Cb, A].first
p kk.new.has
