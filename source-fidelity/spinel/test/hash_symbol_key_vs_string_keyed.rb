# A Symbol key probed a String-keyed hash by its name: `h[:a]`, `key?`,
# `fetch`, `assoc` and `delete` all found "a"'s entry, and a store through a
# parameter, `h[:x] = 1`, overwrote the String entry. The name coercion was a
# leftover of an older Hash.new{} model; :a != "a", so the probe misses and
# the store widens the caller's literal to a mixed-key hash (#4531,
# elektronaut). A missed delete answers nil, not 0.
h = { "a" => 1 }
p :a == "a"
p h[:a]
p h.key?(:a)
p h.include?(:a)
p h.member?(:a)
p h.has_key?(:a)
p h.fetch(:a, :dflt)
p h.assoc(:a)
p h.dig(:a)
p h.delete(:a)
p h.delete("zz")
p h
k = :a
p h[k], h.key?(k), h.delete(k)
p h

def f(h)
  h[:x] = 1
  h
end
p f({ "x" => 0 })
def g(h)
  h[:x] ||= 1
  h
end
p g({ "x" => 0 })
# the identical store on a local
l = { "x" => 0 }
l[:x] = 1
p l
# two callers with different key kinds, and an or-write on the union
def k(h)
  h[:x] ||= 9
  h
end
p k({ "x" => 0 })
p k({ y: 5 })
# the inverse direction was already right
s = { a: 1 }
p s["a"], s.key?("a"), s.fetch("a", :none)

# the vector2d shape: a String-keyed input read through Symbol keys
class Vec
  attr_reader :x, :y
  def initialize(x, y) = (@x, @y = x, y)
  def self.parse(hash)
    hash[:x] ||= hash["x"]
    hash[:y] ||= hash["y"]
    new(hash[:x], hash[:y])
  end
end
v = Vec.parse({ "x" => 150, "y" => 100 })
p [v.x, v.y]
