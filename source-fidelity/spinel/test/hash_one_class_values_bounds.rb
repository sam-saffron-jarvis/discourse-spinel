# The boundaries of the one-class hash typing (#4846): a second class, an
# escaping hash, a stored nil each keep the values boxed.

class Item
  attr_reader :n
  def initialize(n) = @n = n
end
class Other
  attr_reader :n
  def initialize(n) = @n = n
end
class Store
  def initialize = @items = {}
  def put(k, v) = @items[k] = v
  def get(k) = @items[k]
  def all = @items.values
  def total
    t = 0
    @items.each_value { |v| t += v.n }
    t
  end
end
s = Store.new
s.put("a", Item.new(1))
p s.get("a").n
p s.get("zz")
p s.total
# a store that also takes another class stays boxed
class Mixed
  def initialize = @h = {}
  def put(k, v) = @h[k] = v
  def ns = @h.values.map { |x| x.n }
end
m = Mixed.new
m.put("a", Item.new(1))
m.put("b", Other.new(2))
p m.ns
# the hash escapes: passed to a method
class Esc
  def initialize = @h = {}
  def put(k, v) = @h[k] = v
  def hash_out = @h
  def first_n = @h.values.first.n
end
es = Esc.new
es.put("a", Item.new(3))
es.hash_out["b"] = Other.new(4)
p es.first_n
p es.hash_out.size
# local hash
h = {}
h["x"] = Item.new(9)
h.each_value { |v| p v.n }
p h.fetch("x").n
# a hash that stores nil stays boxed, so a value read on it still raises
class NilStore
  def initialize = @h = {}
  def put(k, v) = @h[k] = v
  def each_n
    out = []
    @h.each_value { |v| out << (v ? v.n : :none) }
    out
  end
end
ns = NilStore.new
ns.put("a", Item.new(5))
ns.put("b", nil)
p ns.each_n
