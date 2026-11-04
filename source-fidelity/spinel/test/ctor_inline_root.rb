# A yielding initialize is inlined at the `new` site with self bound to a
# fresh object that, until now, nothing rooted while that body ran. Under
# SPINEL_GC_STRESS=1 the nested-Set shape below looped for ever on the torn
# object; the rest pin the rule for a user class, with and without a block.
require "set"
p Set[1, 2].inspect
sets = (0..1).map { |k| Set[Set[k], Set[k + 10], Set[k + 20]] }
p sets.map(&:inspect)
p sets[0].size
class Box
  attr_reader :items, :tag
  def initialize(items)
    @items = []
    @tag = "t" * 40
    items.each { |x| @items << x }
    yield self if block_given?
  end
end
n = 0
bad = 0
200.times do |i|
  b = Box.new([i, i + 1]) { |bx| bx.items << 0 }
  n += b.items.size
  bad += 1 unless b.tag == "t" * 40 && b.items == [i, i + 1, 0]
end
p [n, bad]
c = Box.new([7])
p [c.items, c.tag.size]
t = Set.new([3, 4]) { |x| x * 2 }
p t.inspect
