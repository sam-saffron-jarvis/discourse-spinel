# A nilable Integer slot answering a method that was migrated to Ruby.
#
# `@i` is sometimes genuinely nil, so the slot carries the SP_INT_NIL
# sentinel while its static type stays a plain Integer. The C emitters these
# eight replaced tested for the sentinel unconditionally; a Ruby body cannot
# see it without asking, so the sentinel went through as an ordinary number:
# each method raised naming its own first operation ("undefined method '<'
# for nil") instead of naming itself, and #fdiv answered 0.0 where CRuby
# raises. Every line below prints what CRuby prints.
class R
  def initialize; @i = nil; end
  def i = @i
  def i=(x); @i = x; end
end

r = R.new
r.i = 3 if ARGV.length > 5   # never taken: the slot stays nil
v = r.i

def show
  p yield
rescue NoMethodError => e
  puts e.message
end

show { v = R.new.i; v.digits }
show { v = R.new.i; v.bit_length }
show { v = R.new.i; v.gcd(4) }
show { v = R.new.i; v.lcm(4) }
show { v = R.new.i; v.gcdlcm(4) }
show { v = R.new.i; v.ceildiv(4) }
show { v = R.new.i; v.remainder(4) }
show { v = R.new.i; v.fdiv(4) }

# The argument check does not run first: CRuby looks the method up on the
# receiver before it coerces anything, so a bad argument on a nil receiver
# still reports the receiver.
show { v = R.new.i; v.digits("x") }

# A slot that does hold a number is untouched.
r.i = 12
p r.i.gcd(8)
p r.i.digits
p r.i.fdiv(8)
