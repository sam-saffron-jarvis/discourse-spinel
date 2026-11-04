# `a * b - c` in one expression is a multiply and a subtraction, each rounded
# to double, in Ruby. The C compiler contracts the pair into a fused
# multiply-add by default (clang: -ffp-contract=on), which rounds once and
# answers a different double a few ULP away, so the generated C and the
# runtime are compiled with -ffp-contract=off. Compared as bit patterns:
# the difference is silent otherwise.
def bits(x) = [x].pack("E").unpack1("Q<").to_s(16)

l0 = 156.25
l1 = 208.333333334
l2 = 1.77951304201
r = l0 * l2 - l1
puts bits(r)
q = -l1 * l0 / r
puts bits(q)

# the same through method parameters, an array and a block
def mad(a, b, c) = a * b + c
def msub(a, b, c) = a * b - c
puts bits(mad(l0, l2, -l1))
puts bits(msub(l1, l0, l2))
v = [l0, l1, l2]
puts bits(v[0] * v[2] - v[1])
puts bits(v.map { |x| x * l2 - l1 }.sum)
acc = 0.0
3.times { |i| acc = acc * l2 + v[i] }
puts bits(acc)
