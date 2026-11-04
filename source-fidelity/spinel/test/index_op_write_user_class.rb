# `recv[k] ||= v`, `recv[k] &&= v` and `recv[k] op= v` on an instance of a
# user class with its own [] and []= are the calls Ruby makes, the receiver
# and the key each evaluated once. They were refused (#5054).
class Bag
  def initialize = @h = {}
  def [](k) = @h[k]
  def []=(k, v)
    @h[k] = v
  end
  def to_s = @h.inspect
end

b = Bag.new
b[:n] ||= 0
b[:n] += 1
b[:n] += 41
p b[:n]
b[:n] ||= 99
p b[:n]
b[:m] &&= 5
p b[:m]
b[:n] &&= b[:n] * 2
p b[:n]
b[:n] -= 4
p b[:n]
b["s"] ||= +"a"
b["s"] += "b"
p b["s"]

$recv = 0
$key = 0
def bag_of(x)
  $recv += 1
  x
end
def key_of(k)
  $key += 1
  k
end
c = Bag.new
bag_of(c)[key_of(:t)] ||= 10
bag_of(c)[key_of(:t)] += 5
p [c[:t], $recv, $key]

r = (c[:u] ||= 7)
p r

class Stat
  def initialize = @ctx = Bag.new
  def step(value)
    @ctx[:n] ||= 0
    @ctx[:sum] ||= 0
    @ctx[:n] += 1
    @ctx[:sum] += value
  end
  def mean = @ctx[:sum] / @ctx[:n]
end
s = Stat.new
[2, 4, 9].each { |v| s.step(v) }
p s.mean
