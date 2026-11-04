# `self.new(&h)` in a class method forwarding its block into a stored-block
# initialize: the Class-value dispatch passed NULL for the block.
class Reg
  def initialize(&h) = @h = h
  def self.make(&h) = self.new(&h)
  def poke(v) = @h.call(v)
end
p Reg.make { |v| v * 2 }.poke(21)
