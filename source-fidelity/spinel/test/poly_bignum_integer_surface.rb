# The Integer surface on a boxed receiver that holds a Bignum (#4665). The
# names Integer alone owns used to be served by narrowing the box to sp_int,
# which truncated a Bignum and computed on the wrong number (bit_length 0,
# pow 1), and gcd, lcm and #[] accepted only a small Integer's tag. Each
# answers by the box's tag now; an answer that can itself be a Bignum
# stays boxed. The same names on a boxed small Integer keep answering as
# before, and a loop that counts in an sp_int says what it cannot do.
# `b.to_i` moved out: #4665 held it at RangeError pending #2024, and promote
# now answers the Bignum, so the raise side lives in float_to_int_out_of_range
# (excluded from the promote run) and the promote side in promote_float_to_int.
def poly(x) = x
p poly("s")
b = poly(18446744073709551615)
p b.bit_length
p b.pred
p b.pow(2)
p b.pow(2, 97)
p b.ceildiv(7)
p b.gcdlcm(6)
p b.digits
p b.digits(1000)
p b.gcd(6)
p b.lcm(6)
p b[0], b[63], b[64], b[-1]
p b.succ
p b.gcd(poly(18446744073709551616))
p b.lcm(poly(18446744073709551616))
p b.ceildiv(poly(-7))
p b.pow(poly(3), poly(18446744073709551629))
n = poly(20)
p n.bit_length, n.pred, n.pow(2), n.pow(3, 7), n.ceildiv(6), n.gcdlcm(15), n.digits, n.gcd(15), n.lcm(15), n[2], n[4]
p poly(-20).ceildiv(6), poly(-7).digits(2) rescue p $!.class
lim = poly(23)
n.upto(lim) { |i| print i, " " }
puts
n.downto(lim - 5) { |i| print i, " " }
puts
p poly(2**64).pred.pred
p poly(2**63).pred.class
