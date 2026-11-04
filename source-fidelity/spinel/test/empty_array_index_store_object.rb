# An empty array filled by index assignment with objects (#4512): the object
# array store used the fixed-shape setter, which drops a store past the end,
# so `banks = []; banks[0] = Rom.new(42)` left the array empty and the read
# crashed. The store follows Ruby's index rules: grow with nil, count a
# negative index from the end, IndexError below -len.
class Rom
  def initialize(n) = @n = n
  def n = @n
end

banks = []
banks[0] = Rom.new(42)
banks[3] = Rom.new(7)
p banks.length
p banks[0].n
p banks[3].n
p banks[1].nil?
banks[-1] = Rom.new(8)
p banks[3].n
p banks.map { |b| b ? b.n : nil }

class Cart
  def initialize = @roml = []
  def load(bank, v) = @roml[bank] = Rom.new(v)
  def bank(i) = @roml[i]
  def size = @roml.size
end
c = Cart.new
c.load(2, 5)
c.load(0, 1)
p c.size
p c.bank(2).n
p c.bank(0).n
begin
  banks[-10] = Rom.new(0)
rescue IndexError => e
  puts e.message
end
