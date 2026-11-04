# Comparable#clamp on a boxed numeric compared its operands through doubles,
# so a Bignum receiver against an Integer bound at the edge of the word came
# back unchanged: 2**63 and 2**63 - 1 are one double. This is wasm's
# trunc_sat (truncate the float, then clamp into the integer range). The
# comparisons are exact now, in both modes, and the applied operand keeps
# its class as before.

def cl(t, min, max) = t.clamp(min, max)

big = [2**63, nil][0]
p big.clamp(-2**63, 2**63 - 1)
p cl(big, -2**63, 2**63 - 1)
p cl(-(2**63) - 1, -2**63, 2**63 - 1)
p cl(2**64, 0, 2**64 - 1)
p cl(2**64, 0, 2**63)
p cl(big, 0, 10)
p cl(5, -2**63, 2**63 - 1)
p cl(big, 2**63, 2**63 + 1)

# one-sided
p big.clamp(nil, 2**63 - 1)
p big.clamp(2**63 + 1, nil)
p big.clamp(nil, nil)

# a range: an open side is not a bound
p big.clamp(0..)
p big.clamp(..10)
p big.clamp(0..10)
bigneg = [-(2**70), nil][0]
p bigneg.clamp(..0)
p bigneg.clamp(-10..)

# the applied operand keeps its class
p big.clamp(0, 1.5)
p big.clamp(0.5, 2**64)
p [1.5, nil][0].clamp(2, 3)

# the failed comparisons keep their words
begin
  cl(big, 10, 1)
rescue ArgumentError => e
  puts e.message
end
begin
  cl(big, 0, Float::NAN)
rescue ArgumentError => e
  puts e.message
end
begin
  cl([Float::NAN, nil][0], 0, 1)
rescue ArgumentError => e
  puts e.message
end
