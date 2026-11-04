# pop / shift / max / min answer nil on an empty array. Two things made them
# answer a number instead (#4288).
#
# The float array helpers returned 0.0 where the int ones already returned
# SP_INT_NIL, so a drained float array read back as a real zero.
#
# And an empty literal's element type is unknown, so the read goes through the
# poly array and is narrowed into the slot: that narrowing used sp_poly_to_i,
# which answers the 0 underneath the nil tag. Narrowing into a slot is not
# #to_i -- nil there is the slot's own sentinel.

a = [1.5, 2.5]
p a.pop
p a.pop
p a.pop

b = [3.5]
b.pop
p b.shift
p b.max
p b.min

c = [].pop
p c
d = [].shift
p d
e = [].max
p e
f = [].min
p f

# the int side, drained the same way
g = [1, 2]
p g.pop
p g.pop
p g.pop
p g.shift
p g.max
p g.min

# and a non-empty receiver is unchanged
h = [3, 1, 2]
p h.max
p h.min
p h.pop
p h.shift

# nil narrowed into a float slot keeps the float sentinel, and into an int
# slot the int one -- a real zero still reads as zero
i = [0.0]
p i.pop
p i.pop
j = [0]
p j.pop
p j.pop
