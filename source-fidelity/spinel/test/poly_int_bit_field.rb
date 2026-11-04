# Integer#[start, len] -- the len-bit field starting at bit `start` -- on a
# BOXED receiver. The typed arms have answered it all along; a boxed one fell
# past the slice helper's Integer case to its nil default, so the read came
# back nil and went on being used as a number. The one-argument form (a single
# bit) was never affected, which is why this hid: a program that reads bits one
# at a time is fine and one that reads a field is not.
n = [0b1011010, nil][0]
p n[1, 3]
p n[0, 4]
p n[2]

# the same value reached through a method whose return nothing types --
# the shape that turns a typed receiver into a boxed one
def thru(x); x; end
p thru(255)[0, 4]
p thru(255)[4, 4]

# out-of-range start and len keep CRuby's two's-complement answers rather than
# an undefined shift
b = [255, nil][0]
p b[2, 100]
p b[-1, 3]
p b[2, -1]
p b[0, 0]
p b[100, 4]
neg = [-1, nil][0]
p neg[60, 8]

# a Bignum receiver answers the same way
big = [2**70 + 0b1011, nil][0]
p big[0, 4]
p big[70, 2]
p big[0, 0]
