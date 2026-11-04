# spinel: int64 -- assumes a 64-bit Integer (Bignum operands need it)
# Integer#ceildiv, in Ruby (builtins/integer.rb). CRuby's own algorithm
# (there is no source to read here, so found by black-box probing a
# coerce-tracing stub class): negate the argument first (a real call to
# its own unary `-@`), floor-divide, negate the quotient --
# `-(self.div(-other))`. Two engine gaps this exposed, both fixed
# alongside the migration:
#
# 1. The REQUIRED-parameter pitfall gcd's own commit found: a single
#    `if other.is_a?(Integer) ... else raise ... end` (the gcd shape)
#    does not work here because Float has to keep computing, not raise
#    -- so each accepted type gets its own is_a? arm (narrowing `other`
#    for codegen), and the final `else` never touches `other`'s type at
#    all. `test/integer_gcd_arg_check.rb`-style Array/Hash/Symbol/nil/
#    true/false arguments below pin that this still compiles and
#    answers CRuby's exact simplification (a generic TypeError, not the
#    real NoMethodError CRuby raises for `-@`) the unmigrated compiler
#    already answered for the same inputs -- not a new gap.
# 2. `Integer#div` with a statically Bignum-typed argument on an int
#    receiver failed to COMPILE (emit_int_divisor had no TY_BIGINT
#    case, so sp_idiv got a raw pointer). Fixed in codegen_call_recv.c;
#    `3.ceildiv(2 ** 70)` below is what surfaced it.
#
# Not covered here (found, pre-existing, unrelated to this migration --
# see the commit message): a Bignum receiver's Integer#div(Float) and
# Integer#div(0.0) both already answer wrong/nil on the unmigrated
# compiler, identically before and after this change; and a program's
# own reopen of a builtin primitive method is silently ignored for a
# CONCRETE receiver (not just a migrated one -- `Integer#abs` shows the
# identical gap), a general pre-existing limitation out of scope here.

def safe
  yield
rescue => e
  [e.class, e.message]
end

def pick(v) = v

p safe { 7.ceildiv(2) }
p safe { (-7).ceildiv(2) }
p safe { 7.ceildiv(-2) }
p safe { (-7).ceildiv(-2) }
p safe { 0.ceildiv(5) }
p safe { 7.ceildiv(1) }
p safe { 7.ceildiv(7) }
p safe { 1.ceildiv(7) }
p safe { 7.ceildiv(2.0) }
p safe { 7.ceildiv(2.5) }
p safe { (-7).ceildiv(2.5) }
p safe { 7.ceildiv(-2.5) }
p safe { 7.ceildiv(0) }
p safe { 7.ceildiv([1, 2]) }
p safe { 7.ceildiv({ a: 1 }) }
p safe { 7.ceildiv(:sym) }
p safe { 7.ceildiv(nil) }
p safe { 7.ceildiv("2") }
p safe { 7.ceildiv(true) }
p safe { 7.ceildiv(false) }

# Bignum receiver and/or argument
p safe { (2 ** 70).ceildiv(3) }
p safe { (2 ** 70).ceildiv(2 ** 69) }
p safe { (2 ** 70).ceildiv(-3) }
p safe { (-(2 ** 70)).ceildiv(3) }
p safe { 3.ceildiv(2 ** 70) }

# a run-time-typed (poly) receiver stays on the existing dispatch
# (sp_poly_int_ceildiv), uncontested by any user class
p safe { pick(7).ceildiv(2) }
p safe { pick(2 ** 70).ceildiv(3) }

# a user class sharing the name: same arity and a different one, both
# on the poly-dispatch collision path (see poly_numeric_collision.rb)
class Widget
  def ceildiv(x) = "widget"
end
class WidgetDiffArity
  def ceildiv(x, y) = "widget-diff-arity"
end
p safe { pick(Widget.new).ceildiv(1) }
p safe { pick(7).ceildiv(2) }
p safe { pick(WidgetDiffArity.new).ceildiv(1, 2) }
p safe { pick(7).ceildiv(2) }
