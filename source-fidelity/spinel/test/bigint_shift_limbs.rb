# A Bignum shift moves limbs; it does not build 2**n and multiply or divide
# by it. The answers must not move with the method: a right shift FLOORS,
# and shifting the magnitude and keeping the sign would truncate toward zero
# instead -- the two differ for every negative value that loses a set bit.
def show(v, s)
  puts "#{v} >> #{s} = #{v >> s}"
  puts "#{v} << #{s} = #{v << s}"
end

big = 2**100
odd = -(2**100) - 1

# the floor, at every place a bit can be lost
p odd >> 1
p odd >> 63
p odd >> 64
p odd >> 65
p odd >> 100
p odd >> 101
p odd >> 1000
# an exact negative shift loses nothing and keeps the same answer either way
p(-big >> 1)
p(-big >> 100)
p(-big >> 101)

show(big, 0)
show(big, 63)
show(big, 64)
show(big, 65)
show(-big - 7, 3)
show(3**200, 127)

# a negative count is the other shift
p big >> -8 == big << 8
p big << -8 == big >> 8

# and the round trip over a wide value
x = 7**400
p ((x << 251) >> 251) == x
p ((-x - 1 << 251) >> 251) == -x - 1
