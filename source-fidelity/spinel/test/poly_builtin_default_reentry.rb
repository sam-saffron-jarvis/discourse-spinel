# A builtin receiver reaching the poly method dispatch because a user class
# owns the name, for a name nothing wrote an arm for.
#
# The dispatch's default arm was a chain of hand-written cases, one per name,
# and a name nobody had added raised NoMethodError for a method the receiver
# has. The same gap was found and patched three times over the numeric names
# alone. The default now asks the ordinary call emission what a builtin
# receiver would answer -- the re-entry the container arm (#3459) and the
# String tag pre-arm (#4816) already use -- so a name no table carries gets
# whatever the surface serves.
#
# `Shadow` defines each name with two parameters and every call below passes
# none, so no user arm is a candidate and the answer has to come from the
# receiver itself.
# The names below are the ones the change actually gave arms to, counted from
# the corpus sweep: to_a by a long way (371 sites), then the container reads
# and the numeric queries. Covering them here is the point -- the sweep found
# 102 files whose C changed and not one whose OUTPUT did, which says the suite
# never reaches these arms on a builtin receiver, so nothing but this file
# tests them.
class Shadow
  def all?(a, b) = :shadow
  def sum(a, b) = :shadow
  def to_sym(a, b) = :shadow
  def to_a(a, b) = :shadow
  def min(a, b) = :shadow
  def max(a, b) = :shadow
  def first(a, b) = :shadow
  def last(a, b) = :shadow
  def length(a, b) = :shadow
  def reverse(a, b) = :shadow
  def inspect(a, b) = :shadow
  def to_s(a, b) = :shadow
  def keys(a, b) = :shadow
  def values(a, b) = :shadow
  def sort(a, b) = :shadow
end

def pick(x) = x

s = Shadow.new
p s.all?(1, 2)
p s.sum(1, 2)
p s.to_sym(1, 2)
p s.to_a(1, 2)

p pick(1).class
p pick(7.5).class

def show
  p yield
rescue NoMethodError => e
  puts "NoMethodError: #{e.message[/method '[^']*'/]}"
end

show { pick([3, 1, 2]).all? }
show { pick("abc").sum }
show { pick(:abc).to_sym }
show { pick([3, 1, 2]).to_a }
show { pick((1..4)).to_a }
show { pick([3, 1, 2]).min }
show { pick([3, 1, 2]).max }
show { pick([3, 1, 2]).first }
show { pick([3, 1, 2]).last }
show { pick([3, 1, 2]).length }
show { pick([3, 1, 2]).reverse }
show { pick([3, 1, 2]).sort }
show { pick([3, 1, 2]).inspect }
show { pick([3, 1, 2]).to_s }
show { pick({"a" => 1, "b" => 2}).keys }
show { pick({"a" => 1, "b" => 2}).values }
show { pick({"a" => 1, "b" => 2}).length }

# a receiver the surface cannot serve keeps its NoMethodError: the runtime
# helper the arm ends in asks the tag, and nothing else answers for it
class Bare; end
begin
  p pick(Bare.new).to_a
rescue NoMethodError => e
  puts "NoMethodError"
end
