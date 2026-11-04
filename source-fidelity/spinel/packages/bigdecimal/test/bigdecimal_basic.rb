# The minimal BigDecimal (#4881): construction, the four operations with
# BigDecimal, Integer and Float on either side, comparison, and the
# conversions. The .expected file is CRuby's output with its own
# bigdecimal; a quotient is compared through to_f, since CRuby picks the
# division precision per operation.
require "bigdecimal"

a = BigDecimal("1.25")
b = BigDecimal(3)
p a, b, BigDecimal("-0.005"), BigDecimal("12e3"), BigDecimal("0"), BigDecimal("1_000.5")
p a + b, a - b, a * b, b - a, -a, a.abs, BigDecimal("-2.5").abs
p a + 1, 1 + a, a * 2, 2 * a, a - 0.25, 0.25 + a
p (a / b).to_f, (1 / b).to_f, (b / 7).to_f, (BigDecimal("1.281551565545") / 9).to_f
p a < b, a > b, a == BigDecimal("1.250"), a == 1.25, b == 3, a <=> b, [b, a].min
p BigDecimal("0.5").clamp(0, 1), BigDecimal("1.5").clamp(0, 1), BigDecimal("-2").clamp(0..1)
p a.to_f, a.to_i, BigDecimal("-7.9").to_i, BigDecimal("12e3").to_i, a.to_s
p Math.sqrt(BigDecimal(2)), Math.sqrt(BigDecimal("0.25"))
p a.zero?, BigDecimal("0").zero?, a.positive?, (-a).negative?
begin
  BigDecimal("abc")
rescue ArgumentError => e
  puts "ArgumentError: #{e.message}"
end

# the Wilson score lower bound lobsters computes (#4881)
ups = 7
downs = 2
n = BigDecimal(ups + downs)
z = BigDecimal("1.281551565545")
phat = BigDecimal(ups) / n
left = phat + (1 / (2 * n) * z * z)
right = z * Math.sqrt((phat * ((1 - phat) / n)) + (z * z / (4 * n * n)))
under = 1.0 + ((1.0 / n) * z * z)
puts ((left - right) / under).clamp(0..1).to_f
