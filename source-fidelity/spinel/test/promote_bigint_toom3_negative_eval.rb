# Toom-3 multiplies at -1 by x0 - x1 + x2, negated when x1 outweighs the
# other two; the negation lost its carry with 16-bit limbs (MRB_NO_MPZ64BIT).
# Ported with the fix from mruby b3c313d8. `a` is a sum of powers of two,
# so the product needs no multiplication to check.
n = 3840
a = (1 << (n - 1)) + (1 << (2 * n / 3)) - (1 << (n / 3))
b = ((7 ** 1400) & ((1 << n) - 1)) | (1 << (n - 1))
times_a = ->(v) { (v << (n - 1)) + (v << (2 * n / 3)) - (v << (n / 3)) }
p times_a.(b) == a * b
p times_a.(b) == b * a
p times_a.(a) == a * a
p(-times_a.(b) == -a * b)
