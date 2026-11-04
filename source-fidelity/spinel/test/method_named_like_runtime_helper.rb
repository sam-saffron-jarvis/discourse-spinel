# An instance method named `scan` or `new` collided with the generated GC
# scan function or constructor of its class, so the C did not compile (#4829).

class Pad
  def initialize = @keys = []
  def press(k) = @keys << k
  def scan(a, b) = @keys.empty? ? [a, b] : [a & b, a | b]
end
pad = Pad.new
pad.press(1)
p pad.scan(6, 3).first
class Base
  def initialize = @xs = [1]
  def scan = @xs.size
end
class Kid < Base; end
p Kid.new.scan
S = Struct.new(:a) do
  def scan = a.size
end
p S.new([1, 2]).scan
class Fac
  def initialize = @items = []
  def new(x) = (@items << x; @items.size)
end
f = Fac.new
p f.new(5)
p f.new(6)
class Mk
  def self.new(x) = "made #{x}"
end
p Mk.new(3)
