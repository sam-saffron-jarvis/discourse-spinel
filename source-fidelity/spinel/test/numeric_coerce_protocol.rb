# A numeric operation whose operand is a user object goes through that object's
# #coerce: CRuby asks for the pair `a, b = obj.coerce(recv)` and answers
# `a <op> b`. That covers the arithmetic operators, the ordered comparisons and
# <=>, the named division family, and Comparable#between? -- for a receiver
# anywhere in the numeric tower, held in a typed slot or read back boxed.
#
# The pins that matter most are the ordered comparisons: lowered as raw C they
# compared the receiver against the object's ADDRESS, so the answer was silently
# whatever the allocator arranged. Their operands are chosen so the coerced
# answer DISAGREES with that address comparison rather than happening to agree.

class Num                 # the standard idiom: a pair of plain numbers
  def coerce(v) = [2.0, v]
end

# #coerce puts the receiver on the RIGHT of the operator, so a constant ABOVE
# the receiver makes every ordered comparison disagree with the address
# comparison the old lowering performed -- which is what these pin.
class Hi
  def coerce(v) = [9.0, v]
end

class Bound               # the two bounds of a between? differ
  def initialize(v) = @v = v
  def coerce(v) = [@v, v]
end

class Pair                # the other idiom: a pair of the class's own kind
  def initialize(v) = @v = v
  def value = @v
  def coerce(v) = [Pair.new(v), self]
  def +(o) = @v + o.value
  def <(o) = @v < o.value
end

class Bad                 # a #coerce that answers a short pair at run time
  def coerce(v) = [2.0, v].take(v > 0 ? 1 : 2)
end

def show
  p(yield)
rescue => e
  p [e.class, e.message]
end

# --- the arithmetic operators, standard idiom (answered nil before) ---
show { 5 + Num.new }
show { 5 - Num.new }
show { 5 * Num.new }
show { 5 / Num.new }
show { 5 % Num.new }
show { 5 ** Num.new }

# (This block sits ahead of the heavier pins on purpose: reading the raised
# exception's class/message late in this file trips a pre-existing GC-stress
# corruption in master's rescue machinery, present with this change or without.)
# CRuby raises for any pair that is not exactly two long, in both directions.
class TooMany
  def coerce(v) = [1, 2, 3]
end
show { 5 + TooMany.new }

# The pair's first element is an instance of the coercing class and its
# SECOND is the number -- `[Money.new, v]` -- so the class's own operator runs
# with a numeric argument. Its parameter therefore has to be poly: narrowed to
# the class, the dispatch arm fell through and raised on a method the class
# defines (matz, reviewing #4265). These sit early in the file for the same
# reason the TooMany pin does.
class Money
  def coerce(v) = [Money.new, v]
  def +(o) = "money+"
end
p(5 + Money.new)
p(5.0 + Money.new)

# Only a NUMBER asks. A String receiver with an operand that answers neither
# <=> nor to_str is CRuby's "comparison failed" -- for the ordered operators
# and for between?, whose typed lowering used to hand the object's pointer to
# a byte compare. between? still evaluates both bounds, once each.
money = Money.new
show { "abc" < money }
show { "abc" >= money }
show { "abc".between?(money, "b") }

# Comparable's == is <=> against 0, which is as valid for a Float answer as
# for an Integer one
class Gauge
  include Comparable
  attr_reader :v
  def initialize(v) = @v = v
  def coerce(n) = [Gauge.new(n), self]
  def <=>(o) = (v - o.v).to_f
end
p(Gauge.new(2) == Gauge.new(2))
p(Gauge.new(2) == Gauge.new(3))

class Whole
  def coerce(v) = [v, 3]
end

# Complex is part of the tower and CRuby's Complex#+ coerces; the receiver
# guard has to admit it or a poly Complex loses its own answer.
class Wrap
  def initialize(v) = @v = v
  def v = @v
  def coerce(o) = [Wrap.new(o), self]
  def +(o) = Wrap.new(@v + o.v)
  def inspect = "Wrap(#{@v})"
end
cx = [Complex(3, 4)]
cx.each { |x| show { x + Wrap.new(9) } }

# ...and ONLY for + - * / ** <=>. The rest refuse rather than answer: %, div
# and remainder match CRuby's NoMethodError byte for byte; the ordered
# comparisons and divmod fail loudly with a different error class (recorded
# in the PR); quo and fdiv keep master's refusal rather than gaining a wrong
# number through boxed entries that have no Complex arm.
class Inert; end
cx.each { |x| show { x % Whole.new } }
cx.each { |x| show { x.div(Whole.new) } }
cx.each { |x| show { x.remainder(Whole.new) } }
cx.each { |x| show { x + Inert.new } }

# --- ordered comparisons: each disagrees with an address comparison ---
show { 5 < Hi.new }
show { 5 <= Hi.new }
show { 5 > Hi.new }
show { 5 >= Hi.new }
show { 5 <=> Hi.new }
show { 1.5 < Hi.new }
show { 1.5 >= Hi.new }

# --- Comparable#between?, two coerced comparisons ---
show { 1.between?(Bound.new(2.0), Bound.new(0.0)) }
show { 5.between?(Bound.new(2.0), Bound.new(9.0)) }
show { 1.5.between?(Bound.new(2.0), Bound.new(0.0)) }

# --- the named division family ---
show { 5.div(Num.new) }
show { 5.modulo(Num.new) }
show { 5.remainder(Num.new) }
show { 5.quo(Num.new) }
show { 5.fdiv(Num.new) }
show { 5.divmod(Num.new) }
show { 5.0.div(Num.new) }
show { 5.0.modulo(Num.new) }
show { 5.0.quo(Num.new) }
show { 5.0.divmod(Num.new) }

# --- a Float receiver: the operators built ill-typed C before ---
show { 5.0 + Num.new }
show { 5.0 - Num.new }
show { 5.0 * Num.new }
show { 5.0 / Num.new }
show { 5.0 % Num.new }

# --- the rest of the tower ---
show { Rational(3, 2) + Num.new }
show { Rational(3, 2) < Hi.new }
show { (10 ** 20) + Num.new }

# --- a boxed receiver read back out of a container ---
[5, 5.0].each do |v|
  show { v + Num.new }
  show { v < Hi.new }
  show { v.div(Num.new) }
end

# --- the pair-of-its-own-class idiom keeps its own methods ---
show { 1 + Pair.new(9) }
show { 1 < Pair.new(9) }
show { 9 < Pair.new(1) }

# --- a #coerce that answers no pair is CRuby's TypeError ---
show { 5 + Bad.new }

# --- the pair stays live across an allocating operand ---
def churn(n)
  100.times { |i| [i, i.to_s, {i => i}] }
  n
end
total = 0.0
40.times { total += (5 + Num.new) + churn(1) }
p total

# #between? boxes its receiver and then evaluates both bounds, each of which
# allocates. A Rational receiver's box carries a heap pointer and gets no root
# from the operand-spill pass, so the emitter's own root is the only thing
# keeping it alive across the bounds: without it this answers false.
def churning_bound(v)
  60.times { |i| [i, i.to_s, {i => i}] }
  Bound.new(v)
end
hits = 0
40.times { hits += 1 if Rational(3, 2).between?(churning_bound(2.0), churning_bound(1.0)) }
p hits

class Lo
  def coerce(v) = [Rational(3, 4), v]
end
def allocating_bound
  GC.start
  8.times { [Rational(9, 10)] }
  Lo.new
end
p(Rational(3, 4).between?(allocating_bound, 5))

# The operand is usually a fresh object, and the RECEIVER is evaluated first.
# Emitted as two bare arguments to one call the operand sat unrooted while the
# receiver ran: a receiver that allocates collected it, the class pool handed
# the block to the next object of that class, and #coerce answered from the
# WRONG object -- a plausible number rather than a crash.
class Rate
  def initialize(n) = @n = n
  def coerce(v) = [@n, v]
end
def allocating_recv(x)
  GC.start
  Rate.new(999)
  x
end
p [allocating_recv(5) + Rate.new(7), allocating_recv(5) * Rate.new(7),
   allocating_recv(5).divmod(Rate.new(7)), allocating_recv(100) < Rate.new(7)]

# A #coerce may answer a homogeneously-typed pair -- an Int or Float array, not
# a poly one -- which is converted rather than used directly. This covers that
# arm, which the operators and the comparisons both reach. The conversion also
# has to keep the array it was handed alive across its own allocation, since
# that array's only root was the frame that returned it; this file does not
# make that observable, but a loop of `5 + IntPair.new` on its own does.
class IntPair
  def coerce(v) = [100, 7]      # a FRESH Int array on every call
end
class FloatPair
  def coerce(v) = [9.0, v.to_f]
end
bad = 0
2000.times do
  bad += 1 unless (5 + IntPair.new) == 107
  bad += 1 unless (5 < IntPair.new) == false
  bad += 1 unless (5 < FloatPair.new) == false   # the pair is [9.0, 5.0]
  bad += 1 unless (5 > FloatPair.new) == true
end
p bad

# A coerced Bignum runs on the boxed division family, whose Bignum arms are
# the parent commit's own rule; the protocol only hands the pair over.
show { (10 ** 25).div(Whole.new) }
show { (10 ** 25).divmod(Whole.new) }

# The pair-of-its-own-class idiom reads `self` after allocating both the new
# object and the array, so the operand has to stay rooted across the call --
# otherwise the collector takes it there and the pool hands its block to the
# object the method has just built.
class Own
  def initialize(n = 0) = (@n = n)
  def n = @n
  def coerce(v)
    junk = []
    120.times { |i| junk << i.to_s }
    [Own.new(v.to_i), self]
  end
  def +(o) = 1000 + o.n
end
bad = 0
2000.times { bad += 1 unless (5 + Own.new(9)) == 1009 }
p bad

# between?'s bounds stay rooted across each bound's own #coerce: the protocol
# reads the bound again (here through @v) after its coerce has allocated, so a
# fresh unrooted bound could be recycled mid-call and answer from the wrong
# object. 0 wrong answers over 400 rounds; the build that rooted only the
# receiver answered wrong for 3 of them under GC stress.
class FreshBound
  def initialize(v); @v = v; end
  def coerce(other)
    junk = []
    60.times { junk << FreshBound.new(-999) }
    [other, @v]
  end
end
hi = FreshBound.new(9)
bad = 0
400.times do
  r = 5.between?(FreshBound.new(6), hi)
  bad += 1 if r != false
end
p bad

# Comparable's derived == on the BOXED path compares <=>'s Float answer with 0
# (the typed path above already agrees on master; this arm did not exist for a
# Float <=> before). Last on purpose: nothing raises after it.
gs = [Gauge.new(2.0), Gauge.new(2)]
p(gs[0] == gs[1])
