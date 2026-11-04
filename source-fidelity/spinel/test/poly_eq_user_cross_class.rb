# A boxed `==` between objects of two user classes asks the receiver's own
# #==. The runtime compared a boxed pair of different classes as unequal
# without asking, and the user-operator table that asks with the argument's
# type checked was only built for a class with an arithmetic operator.
class Loose
  def ==(o) = true
end
class Strict
  def ==(o) = false
end
class Money
  attr_reader :cents
  def initialize(c) = @cents = c
  def ==(o) = o.is_a?(Money) && cents == o.cents
end

p Money.new(1) == Money.new(1)
p [Loose.new] == [Strict.new]
p [Strict.new] == [Loose.new]
x = [Loose.new, 1][0]
p x == Strict.new
p [Loose.new].include?(Strict.new)
p [Strict.new].include?(Loose.new)
p [Money.new(5), 1].include?(Money.new(5))
p [Money.new(5)] == [Money.new(5)]
p [Money.new(5)] == [Money.new(6)]
p [Money.new(5), 2].index(Money.new(5))
