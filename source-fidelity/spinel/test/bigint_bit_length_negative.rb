# Integer#bit_length measures the two's-complement magnitude, so a negative
# value is one shorter than its absolute value at a power of two:
# (-m).bit_length == (m-1).bit_length. sp_bigint_bit_length measured the
# magnitude and answered (-(2**100)).bit_length as 101, where CRuby says 100.
# Both the static Bignum receiver and the boxed one reach it.
def poly(x) = x
p poly("s")

p (2**100).bit_length
p (-(2**100)).bit_length
p (2**64).bit_length
p (-(2**64)).bit_length
p (2**64 + 1).bit_length
p (-(2**64) - 1).bit_length
p (-(2**64) + 1).bit_length
p (2**200).bit_length
p (-(2**200)).bit_length
p (3**200).bit_length
p (-(3**200)).bit_length

# the boxed route
p poly(2**100).bit_length
p poly(-(2**100)).bit_length
p poly(-(2**64)).bit_length
p poly(-(2**64) - 1).bit_length

# small integers are unchanged
p 255.bit_length, (-255).bit_length, (-256).bit_length, (-1).bit_length, 0.bit_length
p poly(255).bit_length, poly(-255).bit_length, poly(-1).bit_length, poly(0).bit_length
