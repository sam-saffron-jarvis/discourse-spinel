# A poly slot holds a small Integer inline, so unboxing one to a Bignum is a
# CONVERSION, not a pointer cast: the two arms of `(x >= 0) ? x : (x & M64)`
# unify on Bignum, and reading the int-tagged arm's payload as an sp_Bigint *
# segfaulted on the first use. Under promote every int local is such a slot.
M64 = 0xffff_ffff_ffff_ffff
def f(x) = (x >= 0) ? x : (x & M64)
p f(2)
p f(0)
p f(-1)
p f(2**63)
p f(2**64 + 5)
def g(x) = x > 10 ? (x * x * x * x * x) : x
p g(3)
p g(1 << 40)
# the converted value keeps flowing as an Integer
p f(2) + 1
p f(-1) & 0xff
p [f(2), f(-2)].map { |v| v + 0 }
p f(-2).zero?
# the signed-wrap twin of the same shape: both arms unify on Bignum again
def s64(x) = x >= 0x8000_0000_0000_0000 ? x - 0x1_0000_0000_0000_0000 : x
p s64(5)
p s64(2**63)
p s64(2**64 - 1)
p s64(2**63 + 7)
