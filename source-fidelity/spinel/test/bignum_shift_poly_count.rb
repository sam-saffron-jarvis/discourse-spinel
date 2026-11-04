# A Bignum receiver shifted by a boxed (poly) count: the count is converted to
# an integer, not cast -- the C cast of an sp_RbVal to int64_t did not build.
# Both directions, zero and past-the-width counts, and a result that flows on
# as a Bignum.
h = {a: 1, b: "s", c: 64, d: 0}
n = h[:a]                       # poly at analysis time, 1 at run time
big = 18446744073709551615      # 2**64 - 1, a Bignum
puts(big << (n & 63))
puts(big >> (n & 63))
puts(big << n)
puts(big >> n)
puts(big << h[:d])              # zero shift: identity
puts(big >> h[:d])
puts(big << h[:c])              # a count past the receiver's own width
puts(big >> h[:c])              # ...and one that consumes it entirely
puts((big << n) + 1)            # the shifted value is still a Bignum
puts((big >> n) * 2)
begin                           # a count with no to_int is CRuby's TypeError,
  puts(big << "str")            # not a shift-width error
rescue TypeError => e
  puts e.message
end
