# Integer / and % by a literal power of two floor as every other divisor
# does. The runtime answers % by one the C compiler can see with a mask
# (a & (b - 1), exact for negatives too); these pin the answers of both
# across signs, against the same divisors held in variables.

vals = [-17, -16, -9, -8, -7, -1, 0, 1, 7, 8, 9, 16, 17,
        9223372036854775807, -9223372036854775807]
vals.each do |a|
  p [a, a / 1, a / 2, a / 8, a / 1024, a % 1, a % 2, a % 8, a % 1024]
end
ds = [1, 2, 8, 1024, 3, -8]
vals.each do |a|
  p ds.map { |d| [a / d, a % d] }
end
x = -13
x /= 4
p x
y = -13
y %= 4
p y
p(-13.div(4), -13.modulo(4), 13.divmod(-4), -13.divmod(4))
p(-5 / -8, -5 % -8)
