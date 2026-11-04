# A walk over an array of one class binds its element into the block
# parameter whatever the block does with it, and a walk whose value is used
# hands on the array itself (#4879).

class H
  def initialize; @h = {}; end
  def []=(k, v); @h[k] = v; end
  def [](k); @h[k]; end
end

a = [H.new, H.new]
a.each { |r| r["X-A"] = "7" }
a.reverse_each { |r| r["B"] = 1 }
a.each_entry { |r| r["C"] = 2 }
a.each_with_index { |r, i| r["D"] = i }
m = a.map { |r| r["E"] = 3 }
c = a.collect { |r| r["F"] = 4 }
p a[0]["X-A"], a[1]["B"], a[0]["C"], a[1]["D"], m, c

# a user []= beside real containers in the same boxed slot
xs = [H.new, {"a" => 1}, [0, 0]]
xs[0]["k"] = 5
xs[1]["b"] = 2
xs[2][1] = 9
p xs[0]["k"], xs[1], xs[2]

class Hd
  attr_reader :n
  def initialize(n); @n = n; end
end
b = [Hd.new(1), Hd.new(2)]
y = b.each_with_index { |r, i| r.n }
p y.size
x = b.each { |r| break r if r.n == 2 }
p x.n
b.each { |r| r = r.n; p r }
b.each { |r| r = nil; p r.is_a?(Hd) }
