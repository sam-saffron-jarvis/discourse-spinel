# --int-overflow=promote answers a Float whose integer value escapes the
# machine word with a Bignum, as CRuby does. raise keeps the RangeError that
# #4657 put in place of an undefined cast, and pins it in
# float_to_int_out_of_range / float_to_int_boundary, which the promote run
# excludes for exactly this reason (the same list int_overflow_raises is on).
#
# What the mode decides is whether a TYPED slot widens. A boxed receiver is
# already boxed, so it answers the Bignum in both modes; the one exception is
# to_i, which #4665 deliberately left raising on a boxed receiver pending
# #2024, so it widens here and not in raise.
f = 2.0**70
p f.floor
p f.ceil
p f.round
p f.truncate
p f.to_i
p f.to_int
p Integer(f)

n = -(2.0**70)
p n.floor
p n.ceil
p n.to_i

# the boxed receiver
def poly(x) = x
p poly("s")
p poly(f).floor
p poly(f).ceil
p poly(f).round
p poly(f).truncate
p poly(f).to_i
p poly(2**64 - 1).to_i

# a literal 0 reaches the same emitter and is exact, so it widens too. A
# NEGATIVE literal does not and still raises -- that form rounds by dividing
# and multiplying in double, which loses bits past 2**53 ((2.0**70).floor(-1)
# came out ...424 for CRuby's ...420) -- so it is left out rather than made
# to answer a wrong number. Not asserted here: the expectation is CRuby's,
# and CRuby answers where this still refuses.
p f.round(0)

# in range, the answer and its class are unchanged
p 3.7.floor, 3.7.to_i, (-3.7).truncate, Integer(3.9)
p 1.2345.round(2)
p 1234.5.round(-1)

# non-finite still has no integer value
begin; (1.0/0).floor; rescue => e; p e.class; end
begin; (0.0/0).round; rescue => e; p e.class; end
begin; Integer(1.0/0); rescue => e; p e.class; end

# promote widens `round(half:)` with no digit count just as it widens the
# keyword-less `round`: the mode picks the tie, never the representability.
f = 1e20
m = :even
p f.round
p f.round(half: :even)
p f.round(half: m)
p f.round(half: "even")
p f.round(0, half: :even)
p f.round(**{ half: :even })
p((-1e20).round(half: :even))
