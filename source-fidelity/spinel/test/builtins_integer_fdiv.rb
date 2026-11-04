# spinel: int64 -- assumes a 64-bit Integer (Bignum operands need it)
# Integer#fdiv, in Ruby (builtins/integer.rb). Always a Float, never
# raising for a zero divisor (7.fdiv(0) is Infinity, matching IEEE754
# float division): `to_f / other`, converting the receiver once, leaves
# the division itself to `/`, which already runs the numeric #coerce
# protocol for a user object and handles Rational/Float/Integer/Bignum
# arguments correctly. The exclusion-list shape (not
# is_a?(Integer)/is_a?(Float)) because `/` silently miscompiles rather
# than failing to compile for a required parameter whose concrete type
# has no numeric meaning at all (confirmed identical and pre-existing on
# the unmigrated compiler via `def f(x, y) = x.to_f / y`), so those
# types are excluded by name and everything else reaches `/` directly.
#
# A genuine engine gap found and fixed writing this (analyze_infer.c):
# an Integer/Bignum arith op with a non-coercible argument was already
# typed as the raising expression's own kind so it could sit in a value
# position (#2471), but only for an Integer/Bignum RECEIVER, never a
# Float one -- even though codegen_call.c's own matching arm (#3645)
# already emits the Float-side raise correctly. `self.to_f / other`
# inside this definition's excluded-argument branch is unreachable at
# run time for those types, but the compiler still needs SOME type for
# it; without the missing TY_FLOAT arm it stayed TY_UNKNOWN, which
# poisoned this whole method's return type to void, and every call to
# fdiv with an excluded-type argument at a DIFFERENT call site failed
# to compile ("void value not ignored") -- caught by this file's own
# Array/Hash/nil/etc probes below, not by hand-inspection.

def safe
  yield
rescue => e
  [e.class, e.message]
end

def pick(v) = v

p safe { 7.fdiv(2) }
p safe { (-7).fdiv(2) }
p safe { 7.fdiv(-2) }
p safe { 7.fdiv(2.5) }
p safe { 7.fdiv(0) }
p safe { 7.fdiv(0.0) }
p safe { (-7).fdiv(0) }
p safe { 0.fdiv(5) }
p safe { 7.fdiv(1) }
p safe { 7.fdiv([1, 2]) }
p safe { 7.fdiv({ a: 1 }) }
p safe { 7.fdiv(:sym) }
p safe { 7.fdiv(nil) }
p safe { 7.fdiv("2") }
p safe { 7.fdiv(true) }
p safe { 7.fdiv(false) }

# Bignum receiver and/or argument
p safe { (2 ** 70).fdiv(3) }
p safe { 3.fdiv(2 ** 70) }
p safe { (2 ** 70).fdiv(2 ** 69) }

# a Rational argument, and the numeric #coerce protocol: `/` already
# handles both, so fdiv does too
p safe { 7.fdiv(Rational(3, 2)) }
class Num
  def coerce(v) = [2.0, v]
end
p safe { 7.fdiv(Num.new) }

# a run-time-typed (poly) receiver stays on the existing dispatch,
# uncontested by any user class
p safe { pick(7).fdiv(2) }
p safe { pick(2 ** 70).fdiv(3) }

# a user class sharing the name: same arity and a different one, both on
# the poly-dispatch collision path (see poly_named_division_collision.rb)
class Widget
  def fdiv(x) = "widget"
end
class WidgetDiffArity
  def fdiv(x, y) = "widget-diff-arity"
end
p safe { pick(Widget.new).fdiv(1) }
p safe { pick(7).fdiv(2) }
p safe { pick(WidgetDiffArity.new).fdiv(1, 2) }
p safe { pick(7).fdiv(2) }
