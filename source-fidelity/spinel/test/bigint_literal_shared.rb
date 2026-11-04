# An out-of-int64 literal is built once per distinct value and shared: an
# Integer is immutable, and the string was re-parsed into a fresh Bignum at
# every use, every time the line ran. Same value twice, different values
# apart, and the sharing must not leak into what the program observes.
A = 0xFFFFFFFF_00000000
B = 18446744073709551615
def mask(x) = x & 0xFFFFFFFF_00000000
def big = 0xFFFFFFFF_00000000
p A
p B
p mask(0xFFFFFFFF_FFFFFFFF)
p big
p big == A
p 0xFFFFFFFF_00000000 + 1
p 0xFFFFFFFF_00000000 - 0xFFFFFFFF_00000000
p [big, big, A].uniq.size
p(-18446744073709551615)
p 18446744073709551615.class
3.times { p 0xDEADBEEF_DEADBEEF }
