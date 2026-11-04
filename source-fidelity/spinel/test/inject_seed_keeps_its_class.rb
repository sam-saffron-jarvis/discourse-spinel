# inject/reduce(seed, :op) makes the SEED the accumulator and applies :op to
# it once per element -- nothing numeric-special. A seed of another class than
# the elements therefore decides the arithmetic, and a seed with no `+` at all
# raises from its own missing method.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

t { [1, 2, 3].reduce(0.5, :+) }
t { [2, 3].reduce(1.5, :*) }
t { [1, 2, 3].reduce(Rational(1, 2), :+) }
t { [1, 2, 3].reduce(10**30, :+) }
t { [1, 2, 3].reduce("x", :+) }
t { [1, 2].reduce("x", :*) }
t { [1, 2].reduce(nil, :+) }
t { [1, 2].reduce(true, :+) }
t { [1, 2].reduce(false, :+) }
t { ["a"].reduce(1, :+) }
t { [1.0, 2.0].reduce(10**30, :+) }
t { [1.0, 2.0].reduce("x", :+) }
t { (1..3).inject(0.5, :+) }
t { (1..3).inject(10**30, :+) }
t { (1..3).inject("x", :+) }
t { (1..3).reduce(false, :+) }
t { ("a".."c").inject(0, :+) }
t { s = :+; [1, 2].reduce(0.5, s) }   # the operator through a local

# the &:op spelling is the same fold: the seed is then the only argument,
# which is how it came to be dropped altogether
t { [1, 2, 3].inject(10, &:+) }
t { [1, 2, 3].inject(0.5, &:+) }
t { [1.5].inject(1, &:+) }
t { [2, 3].inject(1.5, &:*) }
# with a block the lone argument is the SEED, not the operator
t { [1, 2, 3].inject(:s, &:+) }

# nil has no `*` either, and a Float has none of the bit operators
t { [1, 2].reduce(nil, :*) }
t { [2, 3].reduce(7.5, :<<) }

# a user class as the seed, through both spellings of the operator
class Money
  def initialize(cents); @cents = cents; end
  def +(other); Money.new(@cents + other); end
  def inspect; "$#{@cents}"; end
end
t { [1, 2, 3].inject(Money.new(0), :+) }
t { [1, 2, 3].inject(Money.new(0), &:+) }

# the same-class seeds keep the typed fold they always had
t { [1, 2, 3].reduce(10, :+) }
t { [1.0, 2.0].reduce(1, :+) }
t { [].reduce(0.5, :+) }
