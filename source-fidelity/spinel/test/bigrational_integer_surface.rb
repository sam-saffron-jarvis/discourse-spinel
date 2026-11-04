# The Integer surface on a Rational whose numerator is a Bignum. Every name
# here answered NoMethodError -- for a name Rational has -- because the
# rounding and part-reading arms matched only the small sp_Rational box, and
# #to_i went through a double and a cast: past the machine word that
# saturates, and a negative value lands on INTPTR_MIN, which IS the nil
# sentinel, so Rational(-(2**70), 3).to_i answered nil rather than a number.
# The quotient is exact in bigint, and each name rounds the way CRuby does.
br = Rational(2**70, 3)
nb = Rational(-(2**70), 3)
p br.floor, br.ceil, br.round, br.truncate
p nb.floor, nb.ceil, nb.round, nb.truncate
p br.denominator
p br.abs
p nb.abs
p(-br)

# ties break away from zero at Bignum scale, as they do at any other
p Rational(2**71 + 1, 2).round
p Rational(-(2**71 + 1), 2).round
p Rational(7, 2).round
p Rational(-7, 2).round

# a Bignum numerator whose quotient FITS the word is a plain Integer
w = Rational(2**70, 2**69)
p w.to_i, w.floor, w.ceil, w.round, w.truncate, w.numerator, w.denominator

# the same names through a boxed slot
pb = [Rational(2**70, 3), nil][0]
p pb.floor, pb.round, pb.abs, pb.denominator

# `to_int` is Integer's other name for `to_i`, and Integer() truncates a
# Rational toward zero: a boxed Rational answered NoMethodError for the one
# and "can't convert Rational into Integer" for the other, small or large
r  = Rational(5, 2)
pr = [Rational(5, 2), nil][0]
p r.to_int, pr.to_int, Integer(r), Integer(pr)
p pr.numerator, pr.denominator, pr.abs
