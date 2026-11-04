# Enumerable#count's block form is a Ruby definition in
# builtins/enumerable.rb; the blockless (no block, no argument) size query
# and the single-argument equality count stay on their typed emitters
# (desugar_builtin_enum_calls keeps a blockless `count` there for every
# receiver, the way it already does for Range's min/max/minmax/sum/size),
# so a poly Enumerable-includer without its own `size` still answers a
# blockless count by walking `each`, matching CRuby's Enumerable#count.
a = [1, 2, 3, 4, 5]
p a.count
p a.count(3)
p a.count { |x| x > 2 }
p a.count { |x| next 7 if x == 1; nil }
h = { a: 1, b: 2, c: 3 }
p h.count { |k, v| v > 1 }
p h.count
r = (1..10)
p r.count { |x| x.even? }
p a.each_slice(2).count { |x| x.size == 2 }
en = a.count
p en
q = [1, "a", :b, 2.0]
p q.count { |x| x.is_a?(Integer) }
require "set"
st = Set.new([1, 2, 3, 4])
p st.count { |x| x > 2 }
p st.count
p a.count(&:even?)
def fwd(arr, &b) = arr.count(&b)
p fwd(a) { |x| x > 3 }
def ct(&b) = [1, 2, 3].count(&b)
big = ->(x) { x > 1 }
p ct(&big)
p(ct { |x| x < 3 })
class Bag
  include Enumerable
  def initialize(*v) = @v = v
  def each
    @v.each { |x| yield x }
  end
end
bg = Bag.new(10, 20, 30)
p bg.count { |x| x > 15 }
p bg.count
p [].count { |x| true }
p({}.count { |k, v| true })
