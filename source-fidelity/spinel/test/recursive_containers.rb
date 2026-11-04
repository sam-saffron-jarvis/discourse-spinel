# A container walk that meets an object already on its path stops there, the
# way CRuby's rb_exec_recursive does: #inspect prints an ellipsis, == and <=>
# call the repeated pair equal, #hash contributes a fixed value, and #flatten
# and #join raise rather than following the cycle for ever.

a = []
a << a
p a
p [a]
p a.uniq
p a.to_s
p "#{a}"
puts a
print a
puts ""

c = [1]
c << c
p c

x = []
y = [x]
x << y
p x
p y

f = []
f << f
f.freeze
p f

h = {}
h[:h] = h
p h
p h.to_s
p h.to_a
p h.flatten
p({a: h})
k = {}
k[k] = 1
p k
p({a: a}.flatten)

# == / eql? / <=>: a repeated PAIR is equal, and the lengths break the tie
b = []
b << b
p [a == b, a.eql?(b), [a] == [b], a == [a], a == [[a]]]
p [a <=> b, a <=> [a, 1], a <=> a]
p [a, b].uniq.size

g = {}
g[:h] = g
p h == g
n1 = {}
n2 = {}
n1[:x] = { y: n1 }
n2[:x] = { y: n2 }
p n1 == n2

# #hash: the repeated object contributes a fixed value, and the container
# mixes its own length in, so a self-containing array is not [] and not [nil]
p [a.hash == b.hash, a.hash == [].hash, a.hash == [nil].hash, h.hash == {}.hash]

# flatten: only the UNLIMITED walk raises; a counted one prints the ellipsis
begin
  a.flatten
rescue ArgumentError => e
  p e.message
end
d = a.dup
begin
  d.flatten!
rescue ArgumentError => e
  p e.message
end
p [d.size, d[0].equal?(a)]
begin
  [[a]].flatten
rescue ArgumentError => e
  p e.message
end
p a.flatten(1)
p [a].flatten(2)
p a.dup.flatten!(1)

# join has no finite text either
begin
  a.join(",")
rescue ArgumentError => e
  p e.message
end
begin
  [1, [2, a]].join("-")
rescue ArgumentError => e
  p e.message
end
begin
  a * ","
rescue ArgumentError => e
  p e.message
end

# Struct, Data, and a plain object all render the object they are inside
S = Struct.new(:a)
S2 = Struct.new(:a, :b)
s = S.new
s.a = s
p s
p [s]
p({ a: s })
p({ s => 1 })
p s.to_h
p s.to_a
t = S.new
t.a = t
p [s == t, s.eql?(t), s == s]
p [s.hash == S.new(nil).hash, s.hash == t.hash, s.hash == s.hash]
u = S2.new
u.a = u
p u
v = S2.new
w = S2.new
w.a = w
w.b = 3
v.a = w
v.b = 2
p v

D = Data.define(:x)
dd = D.new(x: [])
dd.x << dd
p dd

class Node
  attr_accessor :kids, :parent
  def initialize
    @kids = []
    @parent = nil
  end
end
root = Node.new
kid = Node.new
kid.parent = root
root.kids << kid
p root.inspect.gsub(/0x[0-9a-f]+/, "0xX")

# a raise from inside a walk must not leave the path behind
$armed = false
class Boom
  def inspect
    raise "boom" if $armed
    "B"
  end
end
p [Boom.new, a].inspect
$armed = true
begin
  p [Boom.new, a].inspect
rescue RuntimeError => e
  p e.message
end
$armed = false
p [1, [2]].inspect
p a.inspect
p h.inspect
begin
  a.flatten
rescue ArgumentError
  nil
end
p a.inspect
begin
  a.join(",")
rescue ArgumentError
  nil
end
p a.inspect

# a user #inspect on an element of a recursive container runs once per render
$calls = 0
class Counted
  def inspect
    $calls += 1
    "C"
  end
end
r = [Counted.new]
r << r
p r.inspect
p $calls

# deep but NOT recursive: the guard must not fire
deep1 = []
cur = deep1
1999.times do
  n = []
  cur << n
  cur = n
end
text = deep1.inspect
p [text.size, text.include?("...")]
deep2 = []
cur = deep2
1999.times do
  n = []
  cur << n
  cur = n
end
p [deep1 == deep2, deep1.hash == deep2.hash]

# a non-local exit out of a walk leaves nothing on the path: a raise, a throw,
# a break out of a block and a proc's return all jump over the pops
$exit_kind = nil
$pr = proc { return 11 }
class Jump
  def inspect
    k = $exit_kind
    $exit_kind = nil
    throw(:out, 7) if k == :throw
    if k == :break
      [1].each { break }
      return "J"
    end
    if k == :procret
      $pr.call
      return "J"
    end
    "J"
  end
end
def run_procret
  $pr = proc { return 11 }
  [1, Jump.new].inspect
  99
end
jj = [1, Jump.new]
p jj.inspect
$exit_kind = :throw
p catch(:out) { jj.inspect }
p jj.inspect
p a.inspect
$exit_kind = :break
p jj.inspect
p jj.inspect
p a == b
$exit_kind = :procret
p run_procret
p jj.inspect
p a.inspect
p a.join(",") rescue p $!.message
p [1, [2]] == [1, [2]]

# the eql? a Hash LOOKUP runs takes the same pair guard, so a key that holds
# itself is found by an equal-but-distinct one
p({ a => 1 }[b])
p({ a => 1 }.key?(b))
p({ s => 5 }[t])

# an empty Array and an empty Hash no longer hash alike
p [{}.hash == [].hash, [].hash == [].hash, {}.hash == {}.hash]
# two members with the self-reference first still hash as a number
U2 = Struct.new(:a, :b)
u2 = U2.new(nil, 1)
u2.a = u2
p [u2.hash.class, u2.hash == U2.new(nil, 1).hash]

# a cycle whose repeated element sits deeper than any fixed frame budget
levels = []
inner = []
levels << inner
600.times do
  outer = [inner]
  levels << outer
  inner = outer
end
levels[0] << levels[50]
deep_cycle = inner.inspect
p [deep_cycle.length, deep_cycle.include?("...")]

# past the scan budget the path is indexed: a 2000-deep nest compares, hashes
# and renders in a straight line, a cycle whose repeated element sits far down
# is still found, and a wide array of nests crosses the budget once per element
def nest(n)
  root = []
  cur = root
  n.times do
    m = []
    cur << m
    cur = m
  end
  root
end
d1 = nest(2000)
d2 = nest(2000)
p [d1 == d2, d1.eql?(d2), d1.hash == d2.hash, d1 <=> d2]
leaf = d2
2000.times { leaf = leaf[0] }
leaf << 1
p [d1 == d2, d1.hash == d2.hash, d1 <=> d2]
leaf << d2[0][0][0]
r = d2.inspect
p [r.count("["), r.include?("[...]")]
p d2.hash == d2.hash
begin
  d2.flatten
rescue ArgumentError => e
  p e.message
end
wide = Array.new(50) { nest(40) }
p [wide == Array.new(50) { nest(40) }, wide.hash == Array.new(50) { nest(40) }.hash, wide.inspect.length]
