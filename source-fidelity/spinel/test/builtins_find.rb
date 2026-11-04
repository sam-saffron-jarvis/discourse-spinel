# Enumerable#find / #detect are Ruby definitions in builtins/enumerable.rb
# (detect is find under another name: spinel_parse's alias table triggers the
# splice, desugar_builtins renames the call the way collect_concat->flat_map
# already does). A call reachable from an optional/keyword parameter's
# default value keeps the typed/poly-array emitters instead (a pre-existing,
# general hoist-to-callsite gap unrelated to this migration -- the block
# param's C declaration lands in the method that owns the default rather
# than wherever it is actually evaluated). An Enumerator receiver (including
# a user class with no `each` of its own routed through #3756's
# __to_enum_each synthesis) keeps driving lazily through #next, the way
# take_while already does, so a search on an infinite source still
# terminates.
a = [1, 2, 3, 4, 5]
p a.find { |x| x > 3 }
p a.detect { |x| x > 3 }
p a.find { |x| x > 100 }
p a.find(-> { :none }) { |x| x > 100 }

h = { a: 1, b: 2, c: 3 }
p h.find { |k, v| v > 1 }

r = (1..10)
p r.find { |x| x > 5 }
er = (1..)
p er.find { |x| x > 1000 }

en = a.find
p en.class

q = [1, "a", :b, 2.0]
p q.find { |x| x.is_a?(String) }

require "set"
st = Set.new([1, 2, 3, 4])
p st.find { |x| x > 2 }

p a.find(&:even?)

def fwd(arr, &b) = arr.find(&b)
p fwd(a) { |x| x > 3 }

def fd(&b) = [1, 2, 3].find(&b)
big = ->(x) { x > 1 }
p fd(&big)
p(fd { |x| x < 3 })

class Bag
  include Enumerable
  def initialize(*v) = @v = v
  def each
    @v.each { |x| yield x }
  end
end
bg = Bag.new(10, 20, 30)
p bg.find { |x| x > 15 }
p bg.detect { |x| x > 1000 }

# a next <value>-with-a-nil-tail predicate still carries the value
p a.find { |x| next 7 if x == 1; nil }

# a genuinely infinite each terminates on the first match
class Inf
  include Enumerable
  def each
    i = 1
    loop { yield i; i += 1 }
  end
end
p Inf.new.find { |x| x > 3 }

p [].find { |x| true }
p({}.find { |k, v| true })

# used as a parameter default: evaluated at the call site, where the block
# param has no top-level declaration of its own
A = [1, 2, 3, 4]
def kw(x: A.find { |n| n > 2 })
  x
end
p kw
p kw(x: 99)

def f_ifnone(arr) = arr.find(-> { -1 }) { |x| x > 10 }
p f_ifnone([1, 20, 3])
p f_ifnone([1, 2, 3])
