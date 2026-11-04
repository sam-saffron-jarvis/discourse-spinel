# Kernel#Rational() with an operand whose kind is only known at run time. An
# sp_Rational is a pair of sp_ints, so a Bignum arriving in a box was read
# through it and truncated to its low word: `Rational([2**70, nil][0], 1)`
# answered (0/1), silently, where the same call written with the literal is
# exact. It says so now.
#
# Answering the value instead would mean typing the call poly, which the
# return-type derivation refuses to widen to (g_ret_no_new_poly) -- the same
# #2024 boundary the boxed Bignum conversions sit behind.
def chk(tag)
  puts "#{tag}: #{yield.inspect}"
rescue RangeError => e
  puts "#{tag}: #{e.message}"
end
b  = [2**70, nil][0]
nb = [-(2**70), nil][0]
d  = [3, nil][0]
chk("big/1")   { Rational(b, 1) }
chk("big/3")   { Rational(b, 3) }
chk("big/box") { Rational(b, d) }
chk("negbig")  { Rational(nb, 3) }
chk("big1arg") { Rational(b) }
chk("1/big")   { Rational(1, b) }
# the literal spelling already built the big Rational and still does
p Rational(2**70, 1)
p Rational(2**70, 3)

# operands that fit are the small exact Rational they always were
s = [5, nil][0]
t = [2, nil][0]
p Rational(s, t), Rational(s), Rational(s, 4), Rational(3, t), Rational(5, 2)
f = [2.5, nil][0]
p Rational(f)
r = [Rational(3, 4), nil][0]
p Rational(r, 2)
