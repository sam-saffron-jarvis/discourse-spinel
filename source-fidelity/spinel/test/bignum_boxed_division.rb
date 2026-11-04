# The boxed division family -- what a Bignum held in a poly slot reaches for
# div, /, %, modulo, remainder and divmod -- had no Bignum arm and fell through
# to a 64-bit truncation, so (10 ** 25).div(3) answered a number seven orders
# of magnitude out, with a remainder of 0. The typed receiver paths were right;
# only a receiver or operand that arrives boxed took the truncation. #quo is
# left as it was: its exact answer is a BigRational, and that path loses the
# value under a collector for reasons outside this rule.
big = [10 ** 25, 3]
p [big[0].div(big[1]), big[0] / big[1], big[0] % big[1], big[0].remainder(big[1]),
   big[0].divmod(big[1])]
neg = [-(10 ** 25), 3, 7 ** 30, -6, 10 ** 25]
p [neg[0].div(neg[1]), neg[0] % neg[1], neg[0].modulo(neg[1]), neg[0].remainder(neg[1]),
   neg[0].divmod(neg[1])]
# a Bignum on either side; sign combinations exercise the floor-vs-truncate split
p [neg[2].div(neg[3]), neg[2] % neg[3], neg[2].remainder(neg[3]), neg[2].divmod(neg[3])]
p [neg[1].div(neg[2]), neg[1] % neg[2], neg[1].remainder(neg[2]), neg[1].divmod(neg[2])]
p [neg[3].div(neg[4]), neg[3] % neg[4], neg[3].remainder(neg[4]), neg[3].divmod(neg[4])]
# a quotient small enough to fit back in 64 bits still has to come out exact
p [(2 ** 65).div(2 ** 64), (2 ** 65).divmod((2 ** 64) + 1)]
# a Float operand keeps the float path
p (neg[4] / 2.5).class
# Zero-divisor raises are unchanged by this rule and are NOT pinned here: a
# begin/rescue after these bignum operations trips a pre-existing GC-stress
# crash in master's rescue machinery (the identical program crashes against an
# untouched master runtime), which is its own bug to fix.
