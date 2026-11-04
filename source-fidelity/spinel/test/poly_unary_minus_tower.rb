# Unary minus on a BOXED value went through sp_poly_neg, which handled Float
# and Integer and sent everything else to sp_poly_to_i -- which answers 0 for
# a Rational or a Complex. So `[Rational(1,10)].map { |r| -r }` answered [0],
# silently (#4299). A block parameter over an array of them is boxed, which is
# why `r = Rational(1,10); -r` on a local was always right.
#
# Each kind negates through its own helper now, the way sp_poly_mul dispatches
# its tower.

p [Rational(1, 10), Rational(3, 10)].map { |r| -r }
p [Rational(1, 10), Rational(3, 10), Rational(2, 10)].sort_by { |r| -r }
p [Complex(1, 2), Complex(-3, 4)].map { |z| -z }
p [10**30, -(10**30)].map { |b| -b }

# the two that already worked, and the same values through a local
p [1, 2, -3].map { |x| -x }
p [1.5, -2.5].map { |x| -x }
r = Rational(1, 10)
p(-r)
z = Complex(1, 2)
p(-z)

# the symbol-to-proc spelling reaches the same helper
p [1, -2].map(&:-@)
p [Rational(1, 4)].map(&:-@)

# a mixed array negates each element as its own kind
p [1, 1.5, Rational(1, 2)].map { |n| -n }
