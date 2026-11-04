# `.new(args)` on a Class read out of a container (a boxed receiver) had no
# arm for a Struct or Data class at all, so `REG.fetch(0).new(5, 6)` raised
# NoMethodError. A plain Struct also takes fewer arguments than members
# (the rest are nil) and refuses more with "struct size differs", in both
# the boxed and the Class-value dispatch, as a static `S.new` does.
S = Struct.new(:x, :y)
T = Struct.new(:a) do
  def initialize(a) = super(a + 1)
end
D = Data.define(:u)
class A
  def initialize(x) = @x = x
  def to_s = "A(#{@x})"
end
REG = {0 => S, 1 => T, 2 => A, 3 => D}
p REG.fetch(0).new(5, 6)
p REG.fetch(0).new(9)
p REG.fetch(1).new(5)
puts REG.fetch(2).new(7)
p REG.fetch(3).new(4)
begin
  REG.fetch(0).new(1, 2, 3)
rescue ArgumentError => e
  p e.message
end
def pick(i) = i == 0 ? S : A
p pick(0).new(1)
begin
  pick(0).new(1, 2, 3)
rescue ArgumentError => e
  p e.message
end
