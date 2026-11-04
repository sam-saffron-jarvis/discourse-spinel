# Enumerable#find_index's block form is a Ruby definition in
# builtins/enumerable.rb, written as an accumulator + break rather than
# `return i if yield(x)`: a `return` inside a block only escapes an INLINED
# copy of the method (a plain C `goto`), and a receiver known only at run
# time -- a poly value, or one an instantiated class might answer `each`
# for itself -- walks the generic, non-inlined clone instead, where the
# block is a real Proc called across an actual function call that a goto
# cannot cross. `break`'s non-local exit is built to cross it (the same
# mechanism find/min_by/any? already use).
#
# The value-argument form (`find_index(v)`) and the blockless Enumerator
# form (`find_index` alone) stay on their existing emitters; only the
# block form is this definition (desugar_builtin_enum_calls declines a
# blockless call by name, the way count(v) and any?/all?/none?/one?
# already do).
a = [1, 2, 3, 4, 5]
p a.find_index { |x| x > 3 }
p a.find_index { |x| x > 100 }
p a.find_index { |x| x == 1 }   # a match at index 0, not "not found"

as = ["a", "bb", "ccc", "dddd"]
p as.find_index { |x| x.length > 2 }

af = [1.0, 2.5, 3.5, 4.0]
p af.find_index { |x| x > 3.0 }

h = { a: 1, b: 2, c: 3 }
p h.find_index { |k, v| v == 2 }

r = (1..10)
p r.find_index { |x| x > 5 }
er = (1..)
p er.find_index { |x| x > 100000 }

p a.find_index(3)
p a.find_index(999)
p as.find_index("bb")

en = a.find_index
p en.class

q = [1, "a", :b, 2.0]
p q.find_index { |x| x.is_a?(String) }

require "set"
st = Set.new([10, 20, 30])
p st.find_index { |x| x == 20 }

p ["a", "bb", "ccc"].find_index(&:empty?)

def fwd(arr, &b) = arr.find_index(&b)
p fwd(a) { |x| x == 3 }

def fi(&b) = [1, 2, 3].find_index(&b)
big = ->(x) { x > 1 }
p fi(&big)
p(fi { |x| x < 3 })

class Bag
  include Enumerable
  def initialize(*v) = @v = v
  def each
    @v.each { |x| yield x }
  end
end
bg = Bag.new(10, 20, 30)
p bg.find_index { |x| x > 15 }
p bg.find_index { |x| x > 1000 }

# a poly receiver (a method answering different array types per call site):
# this is the shape that surfaced the `return`-vs-`break` engine gap above,
# and requiring "set" above is what forced the non-inlined clone (any
# Enumerable includer, Set included, now has a real find_index once
# Enumerable#find_index is a Ruby definition, which widens the receiver's
# dispatch even for a call site no Set value ever reaches).
def pick(n)
  n == 0 ? [1, 2, 3] : ["x", "y", "z"]
end
p pick(0).find_index { |x| x == 2 }
p pick(1).find_index { |x| x == "y" }

# a `next`-with-a-nil-tail predicate still carries the value
p a.find_index { |x| next false if x < 0; x == 4 }

# NOTE: unlike find/detect/take_while, find_index has no lazy #next-driven
# Enumerator path (desugar_builtin_enum_calls's `lazy_driven` set), so a
# genuinely infinite Enumerable-includer's find_index hangs materializing
# the whole sequence via #to_a before the search even starts -- true on
# the pre-migration C emitter too (this is not a regression), left for a
# follow-up that gives find_index the same lazy_driven carve-out.

p [].find_index { |x| true }
p (1...1).find_index { |x| true }
p({}.find_index { |k, v| true })

# nested array (array of arrays), and a big index that still fits a
# plain int
aa = [[1, 2], [3, 4], [5, 6]]
p aa.find_index { |x| x.sum == 7 }
big_a = (1..100000).to_a
p big_a.find_index { |x| x == 99999 }
