# spinel: int64 -- assumes a 64-bit Integer (Bignum operands need it)
# Integer#remainder, in Ruby (builtins/integer.rb). Sign follows the
# RECEIVER (unlike `%`/modulo, whose sign follows the divisor):
# (-7).remainder(3) is -1, (-7) % 3 is 2. `%` already answers correctly
# for Integer/Float/Bignum/Rational and runs the #coerce protocol for a
# user object that defines it, so remainder is `%`'s floored answer
# corrected to a truncated sign: when it is non-zero and disagrees in
# sign with the receiver, subtracting the divisor once gives the
# truncated remainder CRuby answers -- no second division, so no
# float round-trip precision loss on a Bignum receiver.
#
# NOT the is_a?(Integer)/is_a?(Float) shape ceildiv/gcd use. A first
# draft used it and broke the numeric #coerce protocol:
# `5.remainder(Num.new)` (Num#coerce defined) is neither Integer nor
# Float, so CRuby's own answer (2.0, via coerce) fell into an "else"
# that raised instead (test/numeric_coerce_protocol.rb, caught before
# landing). `%` (the raw operator, unlike `.div`/`-@` as plain method
# calls) does not fail to COMPILE for a REQUIRED parameter whose
# concrete type has no numeric meaning at all -- it silently
# miscompiles instead (confirmed identical and pre-existing on the
# unmigrated compiler: a required-parameter `%` with a String/Array/
# Hash/nil/true/false-typed argument answers a wrong number or a bogus
# ZeroDivisionError, never a TypeError). So the guard here excludes
# exactly that closed set by name and lets everything else -- Integer,
# Float, Bignum, Rational, a coercible or a plain user object -- reach
# `%` directly; `%`'s own dispatch already raises properly for a user
# object with no #coerce.

def safe
  yield
rescue => e
  [e.class, e.message]
end

def pick(v) = v

p safe { 7.remainder(2) }
p safe { (-7).remainder(2) }
p safe { 7.remainder(-2) }
p safe { (-7).remainder(-2) }
p safe { 0.remainder(5) }
p safe { 7.remainder(1) }
p safe { 7.remainder(7) }
p safe { 7.remainder(2.5) }
p safe { (-7).remainder(2.5) }
p safe { 7.remainder(-2.5) }
p safe { (-7).remainder(-2.5) }
p safe { 7.remainder(2.0) }
p safe { 7.remainder(0) }
p safe { 7.remainder([1, 2]) }
p safe { 7.remainder({ a: 1 }) }
p safe { 7.remainder(:sym) }
p safe { 7.remainder(nil) }
p safe { 7.remainder("2") }
p safe { 7.remainder(true) }
p safe { 7.remainder(false) }

# Bignum receiver and/or argument
p safe { (2 ** 70).remainder(3) }
p safe { (2 ** 70).remainder(2 ** 69) }
p safe { (2 ** 70).remainder(-3) }
p safe { (-(2 ** 70)).remainder(3) }
p safe { 3.remainder(2 ** 70) }

# a run-time-typed (poly) receiver stays on the existing dispatch,
# uncontested by any user class
p safe { pick(7).remainder(2) }
p safe { pick(2 ** 70).remainder(3) }

# a user class sharing the name: same arity and a different one, both on
# the poly-dispatch collision path (see poly_named_division_collision.rb)
class Widget
  def remainder(x) = "widget"
end
class WidgetDiffArity
  def remainder(x, y) = "widget-diff-arity"
end
p safe { pick(Widget.new).remainder(1) }
p safe { pick(7).remainder(2) }
p safe { pick(WidgetDiffArity.new).remainder(1, 2) }
p safe { pick(7).remainder(2) }

# the numeric #coerce protocol still works: Num is neither Integer nor
# Float, but `%` (and so remainder) coerces it. Pins a known pre-existing
# divergence too: real CRuby raises ArgumentError here (its own sign
# check compares the raw uncoerced Num against 0, which Num cannot
# answer), identical on the unmigrated compiler -- see the definition's
# own comment for why matching that exactly is not worth failing to
# compile for every OTHER required-parameter type.
class Num
  def coerce(v) = [2.0, v]
end
p safe { 5.remainder(Num.new) }

# a Rational argument: `%` already handles it, so remainder does too
p safe { 5.remainder(Rational(3, 2)) }
