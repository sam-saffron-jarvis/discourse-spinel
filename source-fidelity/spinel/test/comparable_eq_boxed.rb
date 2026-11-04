# A class that defines <=> and includes Comparable, and no == of its own,
# answers == through <=>. The typed compare did; a boxed one (a block
# parameter over an ivar array, a hash value) reaches it only through the
# boxed binop table, which was generated only for a class with an
# arithmetic operator or a coerce, so `x == m` answered identity.
class Money
  include Comparable
  attr_reader :cents
  def initialize(c) = @cents = c
  def <=>(o) = cents <=> o.cents
end
class Wallet
  def initialize = @items = []
  def add(m) = (@items << m; self)
  def has?(m) = @items.any? { |x| x == m }
end
w = Wallet.new.add(Money.new(5))
p w.has?(Money.new(5))
p w.has?(Money.new(6))
p [Money.new(1), Money.new(2)].max.cents
p Money.new(1) == Money.new(1)
h = {m: Money.new(3)}
p h[:m] == Money.new(3)
