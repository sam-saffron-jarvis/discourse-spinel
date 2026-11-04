# A user `<=>` that accepts more than one kind of operand keeps accepting
# them once a statically typed call site exists for one of them.
#
# The boxed comparison hook (sp_obj_cmp_dispatch) is a caller with no call
# node: sort / min / max / clamp and every Comparable operator on a boxed
# receiver reach `<=>` through it with an operand it cannot know the type of.
# Typed from the resolved call sites alone, the parameter settled on whatever
# those passed -- one `a <=> b` between two Money objects pinned it to Money.
# The body's `other.is_a?(Integer)` arm then folded away as dead, and the
# hook guarded its arm on a Money operand, so `money.clamp(1..5)` raised
# "comparison of Money with 1 failed" for a class that compares them. Drop
# either the bare `<=>` line or the clamp lines and the rest was correct.
class Money
  include Comparable
  attr_reader :cents
  def initialize(cents); @cents = cents; end
  def <=>(other)
    v = other.is_a?(Money) ? other.cents : (other.is_a?(Integer) ? other : nil)
    v.nil? ? nil : (cents <=> v)
  end
  def to_s = "$#{@cents}"
end

def id(x) = x

# the statically typed call site that used to pin the parameter
p(id(Money.new(30)) <=> id(Money.new(10)))
p(id(Money.new(10)) <=> id(Money.new(30)))

# the same `<=>` reached through the hook, with an Integer operand
p id(Money.new(0)).clamp(1..5).to_s
p id(Money.new(9)).clamp(1..5).to_s
p id(Money.new(3)).clamp(1..5).to_s
p id(Money.new(3)).between?(1, 5)
p id(Money.new(9)).between?(1, 5)
p(id(Money.new(7)) > 5)
p(id(Money.new(7)) < 5)

# and with a Money operand, which the narrowed parameter did serve
p id(Money.new(7)).between?(Money.new(1), Money.new(9))

# an operand the class answers nil for is still incomparable
begin
  p(id(Money.new(7)) > "x")
rescue ArgumentError => e
  puts e.message
end

# sort mixes both operand kinds through the same hook
p [Money.new(3), Money.new(1), Money.new(2)].sort.map(&:to_s)
