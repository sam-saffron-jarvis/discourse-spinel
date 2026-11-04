# spinel: int64 -- see poly_int_overflow_raises.rb: the operand has to sit
# just under the sp_int maximum, which no portable literal can name.
# promote answers the same overflow with a Bignum, boxed or typed: the slot
# the number went through cannot change what the number is.
n = [2**62, nil][0]
p n * 2
p n * 4
p n * n
p n + n
p n - (-n)
t = 2**62
p t * 2
p t + t
# and the non-overflowing cases are the plain Integers they always were
p n * 1, n - 1, [3, nil][0] * 4
