# `rand(0x100000000)` is CRuby's own Dir::Tmpname shape, and on a 32-bit
# target that literal is past the target's Integer: the analyzer types the
# call BIGINT while the emitter folded the literal into the sp_int rand, so
# `rand(0x100000000).to_s(36)` handed an sp_int to the Bignum #to_s and the
# C build stopped. A literal past the target's Integer takes the Bignum arm,
# which the 64-bit build already took for a literal past int64.
srand(20260923)
v = rand(0x100000000)
p v.class
p(v >= 0 && v < 0x100000000)
p v.to_s(36).class
p rand(2**70).class
p(rand(2**70) < 2**70)
p rand(10).class
p rand(0).class
p rand(1..3).between?(1, 3)
# a negative bound: the magnitude is what the draw uses. Written with a
# literal past every target's Integer rather than `2**40`, which is a
# RangeError on a 32-bit target under the default overflow mode.
p(-rand(0x100000000) <= 0)
