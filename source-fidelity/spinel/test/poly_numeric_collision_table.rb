# Every name in the poly dispatch's numeric-arm table, in one program.
#
# Each of these reaches the poly method dispatch only because a user class
# owns the name: the ordinary emitter declines a contested name and falls
# through, and the switch's default arm has to answer for a receiver that
# really is a number. The gap was found three times, one or two names at a
# time (gcd/lcm/..., then divmod/remainder/fdiv, then quo/modulo/div), each
# time by someone writing the program below for one name. This covers the
# whole table at once, so the next row is checked the day it is added.
#
# `Shadow` defines each name at an arity the call sites do NOT use, which is
# the shape that leaves the candidate count 0 and still collides: the name is
# taken, so the builtin emitter stands down.
class Shadow
  def gcd(a, b) = :shadow
  def lcm(a, b) = :shadow
  def ceildiv(a, b) = :shadow
  def gcdlcm(a, b) = :shadow
  def pow(a, b, c) = :shadow
  def digits(a, b) = :shadow
  def allbits?(a, b) = :shadow
  def anybits?(a, b) = :shadow
  def nobits?(a, b) = :shadow
  def divmod(a, b) = :shadow
  def remainder(a, b) = :shadow
  def fdiv(a, b) = :shadow
  def quo(a, b) = :shadow
  def modulo(a, b) = :shadow
  def div(a, b) = :shadow
end

def pick(x) = x          # a run-time-typed receiver

n = pick(12)
p n.gcd(8)
p n.lcm(8)
p n.ceildiv(5)
p n.gcdlcm(8)
p n.pow(2)
p n.pow(2, 5)
p n.digits(10)
p n.allbits?(4)
p n.anybits?(4)
p n.nobits?(4)
p n.divmod(5)
p n.remainder(5)
p n.fdiv(5)
p n.quo(4)
p n.modulo(5)
p n.div(5)

# a Bignum receiver takes the same arms
big = pick(2**70)
p big.gcd(8)
p big.divmod(3)
p big.fdiv(2**69)
p big.modulo(7)

# a Float receiver, where the name exists
f = pick(7.5)
p f.divmod(2)
p f.fdiv(2)
p f.quo(2)
p f.modulo(2)
p f.div(2)

# the user class still answers its own method
s = Shadow.new
p s.gcd(1, 2)
p s.divmod(1, 2)
p s.fdiv(1, 2)

# a receiver that is neither raises, naming the method that was called
begin
  p pick("str").gcd(2)
rescue NoMethodError => e
  puts e.message
end
