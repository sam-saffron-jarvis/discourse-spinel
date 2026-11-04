# A program's own reopen of Integer answers a Bignum receiver too, not just
# a small (native-int) one: `class Integer; def abs; 999; end; end` emitted
# the reopened body ONCE, as `sp_Integer_abs(sp_int self)` -- self a native
# int, so a Bignum receiver could not even be passed to it. Any program that
# also held a Bignum anywhere typed the receiver TY_BIGINT rather than poly,
# so the reopen stopped applying to it entirely: `pick(big).abs` and even
# `pick(small).abs`, once a Bignum existed in the same program, answered the
# builtin instead of the reopen.
class Integer
  def abs = 999
  def shout = "int!"
end
def pick(v) = v
small = 5
big = 2 ** 70

# a Bignum receiver, concrete and through a run-time-typed call, honours the
# reopen exactly as a small-Integer receiver does
p small.abs
p big.abs
p pick(small).abs
p pick(big).abs

# a reopened method the compiler has no builtin C emitter arm for keeps
# working on both receiver shapes
p small.shout
p big.shout

# a name the reopen does not define still reaches the builtin, on both --
# Integer#magnitude is CRuby's own alias for the ORIGINAL #abs, made before
# this reopen, so it is unaffected by it, like CRuby
p small.magnitude
p big.magnitude
