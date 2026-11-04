# A user class owning a builtin's name with a DIFFERENT signature.
#
# The builtin emitters stand down for a name any reachable user class owns,
# and they do it by name -- user_defines_or_reads takes no arity. The poly
# method dispatch, which is where such a call lands, asked instead whether a
# user class was a candidate at THIS call site's arity. Where the two
# disagreed the call had nowhere left to go and raised NoMethodError for a
# method the receiver has.
#
# `Shadow` defines each name with two parameters; every call below passes
# one, so no user arm is a candidate and the answer has to come from the
# receiver itself.
class Shadow
  def scan(a, b) = :shadow
  def rpartition(a, b) = :shadow
  def getbyte(a, b) = :shadow
  def gcd(a, b) = :shadow
end

def pick(x) = x

s = Shadow.new
p s.scan(1, 2)
p s.rpartition(1, 2)
p s.getbyte(1, 2)
p s.gcd(1, 2)

# pick answers more than one type, so its value carries its class only at
# run time -- without that there is no dispatch to reach at all.
p pick(1).class
p pick(7.5).class

r = pick("abc")
p r.scan("b")
p r.rpartition("b")
p r.getbyte(0)

n = pick(12)
p n.gcd(8)

# the same names with a MATCHING signature keep taking the user arm for a
# user receiver, and the builtin for a builtin one
class Same
  def scan(a) = :same
end
t = Same.new
p t.scan("b")
p pick("abc").scan("b")
