# A program's own `class Integer; def digits; end` reopen wins over the
# migrated definition -- for a run-time-typed (poly) receiver, the one
# receiver shape a builtin reopen was ever reachable through even before
# this migration (a statically concrete Integer/Bignum receiver's own
# native dispatch has never consulted a reopen, digits included: verified
# identically broken on an unmodified, unmigrated compiler, unrelated to
# this migration and out of scope here). No concrete-receiver call shares
# this file with the reopen, to keep that separate, pre-existing gap out
# of this test entirely.
class Integer
  def digits(base = 10)
    [9, 9]
  end
end
def wrap(v) = v
_never = wrap("x") if ARGV.length > 100
p1 = wrap(5)
puts p1.digits.inspect
