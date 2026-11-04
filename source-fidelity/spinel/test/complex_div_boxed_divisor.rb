# Complex divided by a REAL divides each component: a Float 0.0 gives Infinity,
# an Integer 0 raises ZeroDivisionError. The typed arms have done that since
# the conjugate formula was found to answer NaN for both. A divisor whose kind
# is only known at run time -- read out of a container, or arriving through a
# parameter nothing typed -- was coerced to c+0i and run through the formula
# anyway, so the same zero answered (NaN+NaN*i) where written as a literal it
# raises.
z = [0, nil][0]
begin
  p Complex(20, 40) / z
rescue ZeroDivisionError => e
  puts "boxed int zero: #{e.message}"
end

zf = [0.0, nil][0]
p Complex(20, 40) / zf
p Complex(-20, 40) / zf

# a non-zero boxed divisor answers what the literal answers
two = [2, nil][0]
twof = [2.0, nil][0]
p Complex(20, 40) / two
p Complex(21, 41) / twof

# a divisor reaching a method whose parameter nothing types is boxed too
def dz(a, b); a / b; end
begin
  p dz(Complex(20, 40), 0)
rescue ZeroDivisionError => e
  puts "through a method: #{e.message}"
end
p dz(Complex(20, 40), 4)
p dz(Complex(20, 40), 0.0)

# Complex / Complex keeps the full division
cc = [Complex(2, 0), nil][0]
p Complex(20, 40) / cc
