# Rational's named divisions with an operand whose kind is only known at run
# time. `/` reached the boxed dispatch and `quo` did not, so a Rational
# answered NoMethodError for a method it has -- and one its own `/` already
# served. `fdiv` got further and was turned away by a guard that admits only
# int/float/bigint, inside a function whose very next line divides a Rational.
# A precision argument had a third problem: it was C-cast to an integer, and
# a boxed value is a struct, so the generated C stopped compiling outright.
def quo2(a, b) = a.quo(b)
def fdiv2(a, b) = a.fdiv(b)
def div2(a, b) = a.div(b)
def divmod2(a, b) = a.divmod(b)
def mod2(a, b) = a.modulo(b)
def rem2(a, b) = a.remainder(b)
def rnd2(a, n) = a.round(n)
def trc2(a, n) = a.truncate(n)
def flr2(a, n) = a.floor(n)
def cel2(a, n) = a.ceil(n)

r = Rational(3, 4)
b2 = [2, nil][0]                # a boxed Integer
bf = [0.5, nil][0]              # a boxed Float
br = [Rational(1, 2), nil][0]   # a boxed Rational
p quo2(r, b2)
p quo2(r, bf)
p quo2(r, br)
p fdiv2(r, b2)
p fdiv2(r, bf)
p fdiv2(r, br)
[b2, bf, br].each do |x|
  p div2(r, x)
  p divmod2(r, x)
  p mod2(r, x)
  p rem2(r, x)
end

# the same names with both operands typed still answer as they did
p quo2(r, Rational(1, 2))
p fdiv2(r, Rational(1, 2))
p div2(r, 2), divmod2(r, 2), mod2(r, 2), rem2(r, 2)
p r / 2
# a Rational meeting a Float: divmod read the Float as a Rational (0/1) and
# raised on a divisor that is not zero; remainder went through a double and
# answered 0.75 where the exact value is (3/4)
p Rational(3, 4).divmod(0.5)
p Rational(3, 4).remainder(2)

# a precision that arrives boxed: Rational above the decimal point, Integer
# at or below it, chosen at run time
q = Rational(22, 7)
[2, 0, -1].each do |k|
  n = [k, nil][0]
  p rnd2(q, n)
  p trc2(q, n)
  p flr2(q, n)
  p cel2(q, n)
end
