# Enumerable#any?/#all?/#none?/#one?'s block forms are Ruby definitions in
# builtins/enumerable.rb; the blockless (truthiness) and single-argument
# (pattern `===`) forms stay on their typed emitters -- CRuby's blockless
# any?/all?/none?/one? asks about each element's own truthiness, never the
# block's, so it is not the Enumerator-returning shape the other migrated
# names share. A poly (boxed) array receiver also keeps its typed emitter
# even with a block: that loop re-reads the array's length every turn, which
# a block that shrinks or grows the receiver mid-walk depends on (the
# definition's `each` does not do this for a poly array, see
# boxed_predicate_mutation.rb).
a = [1, 2, 3, 4, 5]
p a.any? { |x| x > 3 }
p a.any? { |x| x > 100 }
p a.any?
p a.all? { |x| x > 0 }
p a.all? { |x| x > 3 }
p a.none? { |x| x > 100 }
p a.none? { |x| x > 3 }
p a.one? { |x| x == 3 }
p a.one? { |x| x > 3 }

h = { a: 1, b: 2, c: 3 }
p h.any? { |k, v| v > 2 }
p h.all? { |k, v| v > 0 }
p h.none? { |k, v| v > 10 }
p h.one? { |k, v| v == 2 }

r = (1..10)
p r.any? { |x| x > 5 }
er = (1..)
p er.any? { |x| x > 1000 }

require "set"
st = Set.new([1, 2, 3, 4])
p st.any? { |x| x > 2 }

p a.any?(&:even?)
p a.any?(Integer)
p a.all?(Integer)
p a.none?(String)

def fwd(arr, &b) = arr.any?(&b)
p fwd(a) { |x| x > 3 }

def av(&b) = [1, 2, 3].any?(&b)
big = ->(x) { x > 2 }
p av(&big)
p(av { |x| x < 1 })

class Bag
  include Enumerable
  def initialize(*v) = @v = v
  def each
    @v.each { |x| yield x }
  end
end
bg = Bag.new(10, 20, 30)
p bg.any? { |x| x > 15 }
p bg.all? { |x| x > 5 }
p bg.none? { |x| x > 1000 }
p bg.one? { |x| x == 20 }

p a.any? { |x| next false if x == 3; x > 3 }

p [].one? { |x| true }
p({}.any? { |k, v| true })

A2 = [1, 2, 3, 4]
def kwa(x: A2.any? { |n| n > 2 })
  x
end
p kwa
p kwa(x: false)
