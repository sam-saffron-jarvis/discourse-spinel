# bare `new(&h)` in a class method: the constructor call left the block
# slot out and the C did not compile.
class Reg
  def initialize(&h) = @h = h
  def self.make(&h) = new(&h)
  def poke(v) = @h.call(v)
end
p Reg.make { |v| v * 2 }.poke(21)
