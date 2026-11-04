# `class << self` inside a Struct.new / Data.define block: its methods were
# class methods of no class, so they were refused, or missing when the
# struct was nested (#4823).

Pair = Struct.new(:a, :b) do
  class << self
    def make(n) = new(n, n * 2)
    def answer = 42
    def via_self(n) = self.new(n, 0)
  end
  def sum = a + b
end
p Pair.make(21).b
p Pair.answer
p Pair.via_self(3).a
p Pair.make(1).sum
Pt = Data.define(:x, :y) do
  class << self
    def origin = new(x: 0, y: 0)
  end
end
p Pt.origin
class Machine
  Pair2 = Struct.new(:a, :b) do
    class << self
      def make(n) = new(n, n * 2)
    end
  end
  DOUBLE = Pair2.make(21)
  def self.double = DOUBLE
end
p Machine::Pair2.make(21).b
p Machine.double.b
