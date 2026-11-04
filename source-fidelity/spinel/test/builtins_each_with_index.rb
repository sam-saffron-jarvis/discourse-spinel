# Enumerable#each_with_index is a Ruby definition in builtins/enumerable.rb:
# the block form (`each { yield x, i; i += 1 }; self`) and the blockless
# Enumerator-of-pairs form (`Enumerator.new { |y| ... }`), specialized per
# call site for typed and boxed receivers, a Hash, a Range, a Set, and a
# user class that includes Enumerable.
a = [10, 20, 30]
p a.each_with_index { |x, i| }
acc = []
a.each_with_index { |x, i| acc << [x, i] }
p acc
e = a.each_with_index
p e.class
p e.to_a
h = { a: 1, b: 2 }
hacc = []
h.each_with_index { |pair, i| hacc << [pair, i] }
p hacc
p (1..3).each_with_index.to_a
require "set"
sacc = []
Set.new([3, 1, 2]).each_with_index { |x, i| sacc << [x, i] }
p sacc
def poly(v) = v
p poly(a).each_with_index { |x, i| }
p poly(a).each_with_index.to_a
class Nums
  include Enumerable
  def initialize(*xs); @xs = xs; end
  def each; @xs.each { |x| yield x }; end
end
n = Nums.new(3, 1, 2)
p n.each_with_index { |x, i| }.equal?(n)
p n.each_with_index { |x, i| }.class
e2 = n.each_with_index
p e2.class
p e2.to_a
def fwd(arr, &b)
  arr.each_with_index(&b)
end
r = []
fwd(a) { |x, i| r << x + i }
p r
e3 = fwd(a)
p e3.class
p e3.to_a
r2 = []
[1, 2, 3, 4, 5].each_with_index do |x, i|
  next if x.even?
  break if i > 3
  r2 << [x, i]
end
p r2
p [10, 20].each_with_index.map { |x, i| x + i }
