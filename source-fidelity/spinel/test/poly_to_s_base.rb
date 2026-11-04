# to_s(base) on a boxed value. A Bignum reached the call as a heap value, not
# as a different method, so it answers in the base too -- it used to fall
# through to the plain rendering and print 2**70 in decimal whatever base was
# asked for. Every other type has a zero-arity to_s, so the argument is
# CRuby's ArgumentError rather than something to ignore.
def poly(x) = x
p poly(3.5)          # the call that boxes the parameter

p poly(255).to_s(16)
p poly(255).to_s(2)
p poly(-255).to_s(16)
p poly(2**70).to_s(16)
p poly(2**70).to_s(2)
p poly(2**70).to_s(36)
p poly(2**70).to_s(10)
p poly(-(2**70) - 1).to_s(36)
p poly(2**70).to_s

# a zero-arity to_s takes no radix
poly("x").to_s(16)  rescue p [$!.class, $!.message]
poly(3.5).to_s(16)  rescue p [$!.class, $!.message]
poly(nil).to_s(16)  rescue p [$!.class, $!.message]
poly(:s).to_s(16)   rescue p [$!.class, $!.message]
poly(true).to_s(16) rescue p [$!.class, $!.message]

# and the radix itself is still checked, on either representation
poly(255).to_s(1)     rescue p [$!.class, $!.message]
poly(255).to_s(37)    rescue p [$!.class, $!.message]
poly(2**70).to_s(1)   rescue p [$!.class, $!.message]
poly(2**70).to_s(99)  rescue p [$!.class, $!.message]

# the base is an expression, evaluated before the call can raise
def base
  puts "base evaluated"
  16
end
poly("x").to_s(base) rescue p $!.class
