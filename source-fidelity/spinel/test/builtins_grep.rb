# Enumerable#grep / #grep_v are Ruby definitions in builtins/enumerable.rb.
# Unlike most methods here, neither arm answers an Enumerator: both compute
# immediately, using plain `pattern === x` (a class, a Range, a Regexp, a
# value compared by `==`, an object defining its own `===`) rather than a
# per-pattern C fold, which is what let this definition close two real
# coverage gaps for free: Hash#grep with a block (its `|k, v|` destructure
# used to mis-bind, and the emitter had no arm for Hash at all) and an
# Enumerator receiver's grep (did not compile).
#
# `arr.grep([1, 2])` (an Array-VALUE pattern, as opposed to `grep(Array)`,
# a class pattern) is not exercised here: `[1, 2] === [1, 2]` itself raises
# NoMethodError today on a concretely-typed Array, a general, pre-existing
# gap unrelated to grep (see the policy proposal).

require "set"

a = [1, 2, "a", 3, "b", 4]
p a.grep(Integer)
p a.grep(Integer) { |x| x * 2 }
p a.grep_v(Integer)
p a.grep_v(Integer) { |x| x.to_s }
p [1, 2, 3, 4, 5].grep(2..4)
p ["foo", "bar", "baz"].grep(/^b/)
p ["aa", "bb", "cc"].grep("bb")
p [1.5, 2.5, "x"].grep(Numeric)
p [].grep(Integer)
p [].grep(Integer) { |x| x }

h = { a: 1, b: 2, c: 3, x: "s" }
p h.grep(Array)
p h.grep(Array) { |k, v| v }
p h.grep_v(Array)

r = (1..10)
p r.grep(3..5)
p r.grep(3..5) { |x| x * 2 }
p r.grep_v(3..5)

e = [1, 2, 3, "x", 4].each
p e.grep(Integer)
e2 = [1, 2, 3].each
p e2.grep(Integer) { |x| x + 1 }

def poly(v) = v
p poly([1, 2, "a"]).grep(Integer)
p poly({ a: 1, b: "s" }).grep(Array)

class Nums
  include Enumerable
  def initialize(*xs); @xs = xs; end
  def each; @xs.each { |x| yield x }; end
end
n = Nums.new(1, "a", 2, "b", 3)
p n.grep(Integer)
p n.grep(Integer) { |x| x * 10 }
p n.grep_v(Integer)

s = Set.new([1, "a", 2, "b"])
p s.grep(Integer).sort
p s.grep(String).sort

class Pred
  def ===(x)
    x > 2
  end
end
p [1, 2, 3, 4].grep(Pred.new)

pr = ->(x) { x.even? }
p [1, 2, 3, 4].grep(pr)

r2 = []
[1, 2, 3, 4, 5].grep(2..4) { |x| r2 << x; x }
p r2

def fwd(arr, pat, &b)
  arr.grep(pat, &b)
end
p fwd([1, 2, 3, 4], 2..3) { |x| x * 100 }
