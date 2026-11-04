# --int-overflow=promote: an Integer `+`, `-` or `*` on a value that never
# passes through a slot (a block parameter, an array element read, a size)
# is typed sp_int at the expression, and took the raising int helper where
# the mode's contract is to promote. It is typed poly now unless both
# operands are known constants, the `<<` and `**` rule, and lowers to the
# promoting sp_poly_add / sub / mul. (promote-only, like the other promote_*
# tests: the default mode raises RangeError here, correctly.)
[2**40].each { |e| p e * e }
x = [2**40]
p x[0] * x[0]
s = "x" * 40
p (2**58) * s.size
p [2**62].map { |e| e + e }
p [-(2**62)].map { |e| e - e - e - e }
p (1..3).map { |i| i * 2 }
p [3, 4].sum { |v| v - 1 }
p [7, 8].map { |v| v * 3 + 1 }.sum
