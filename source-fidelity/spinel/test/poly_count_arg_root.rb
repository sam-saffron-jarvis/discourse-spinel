# count and the four predicates root the array they walk and the argument
# they compare it with.
#
# `count(v)`, `all?(v)`, `any?(v)`, `none?(v)` and `one?(v)` on an object
# array hoist the array and the boxed argument into C temporaries and then
# call the element's == or === on every turn. A user == may allocate, and a
# collection during it frees an array that no Ruby name holds, or an argument
# that was made in the call itself, while the loop is still reading it. Every
# arm below allocates inside == and === for that reason, and takes its
# receiver from a method or its argument from a constructor rather than from
# a local, which would be a root on its own. Each == and === also makes a new
# array and a new K, so a freed receiver's slot and a freed argument's slot are
# both taken by the next comparison, and a stale read answers wrong rather than
# right by luck. Under SPINEL_GC_STRESS=1 master answered count=0, none=true
# and count_chain=0 for the receiver and one_arg=false for the argument; the
# index line, whose emitter roots both, was right all along.
class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
  def ==(o); @arr = [v, o.v, "cmp#{v}"]; @spawn = K.new(v + 100); v == o.v; end
  def ===(o); @arr = [v, o.v, "case#{v}"]; @spawn = K.new(v + 100); v == o.v; end
end
def mkp = (1..40).map { |i| K.new(i) }
k = K.new(7)
puts "count=" + mkp.count(k).to_s
puts "index=" + mkp.index(k).to_s
puts "all=" + mkp.all?(k).to_s
puts "any=" + mkp.any?(k).to_s
puts "none=" + mkp.none?(k).to_s
puts "one=" + mkp.one?(k).to_s
puts "count_chain=" + mkp.reverse.count(k).to_s

# The argument is a temporary too: only the call holds it
held = (1..40).map { |i| K.new(i) }
puts "one_arg=" + held.one?(K.new(7)).to_s
puts "count_arg=" + held.count(K.new(7)).to_s
puts "any_arg=" + held.any?(K.new(41)).to_s

# Both at once, and the Range pattern through this arm, which reaches no user
# code and is rooted the same way
puts "count_both=" + mkp.count(K.new(9)).to_s
puts "any_range=" + mkp.map { |x| x.v.odd? ? x.v : x.v.to_s }.any?(5..6).to_s
