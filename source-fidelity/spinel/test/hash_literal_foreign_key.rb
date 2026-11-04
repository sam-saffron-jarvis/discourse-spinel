# A hash held by an ivar, class variable, global or local is written with keys
# of more than one class across its sites -- the literal's own keys, a store
# in another method, a store through a parameter. Every literal it is assigned
# takes the poly-keyed variant, or the other class's store was dropped, stored
# under a mistyped key, or refused at run time.

# ivar literal, String store in another method
class A
  def initialize = @c = {1 => 2}
  def add = @c["x"] = "y"
  def get = @c
end
a = A.new
a.add
p a.get
p a.get["x"]

# ivar {} keyed by a parameter first, a Symbol elsewhere
class B
  def initialize = @c = {}
  def put(k, v) = @c[k] = v
  def direct = @c[:k] = 2
  def get = @c
end
b = B.new
b.put(1, 2)
b.direct
p b.get, b.get[1], b.get[:k], b.get.keys, b.get.size

b2 = B.new
b2.put("a", "b")
b2.direct
p b2.get, b2.get["a"], b2.get[:k]

# Hash.new, Symbol first, String second
class C
  def initialize = @c = Hash.new
  def put1 = @c[:a] = 5
  def other = @c["b"] = "v"
  def get = @c
end
c = C.new
c.put1
c.other
p c.get, c.get.size

# class variable literal set in the class body
class D
  @@c = {"z" => 3}
  def self.put(k, v) = @@c[k] = v
  def self.other = @@c[7] = "v"
  def self.get = @@c
end
D.put(:a, 5)
D.other
p D.get, D.get[:a], D.get[7]

# global
$g = {1 => 2}
def gput = $g[:b] = 5
gput
p $g, $g[:b]

# local keyed through a block parameter
h = Hash.new
["a"].each { |k| h[k] = 5 }
[0].each { h[:b] = "v" }
p h, h["a"], h[:b]

# the parent's literal, the child's store
class P
  def initialize = @c = {1 => 2}
  def get = @c
end
class Q < P
  def add = @c["x"] = "y"
end
q = Q.new
q.add
p q.get

# one key class, a value of another class stored elsewhere
class E
  def initialize = @c = {"a" => "b"}
  def add = @c["c"] = 4
  def get = @c
end
e = E.new
e.add
p e.get

class F
  def initialize = @c = {1 => 2}
  def add = @c[3] = "s"
  def get = @c
end
f = F.new
f.add
p f.get, f.get[3]

class Cv
  @@c = {"a" => "b"}
  def self.add = @@c["c"] = nil
  def self.get = @@c
end
Cv.add
p Cv.get

$gv = {1 => 2}
def gv_add = $gv[3] = "s"
gv_add
p $gv, $gv[3]

# store, ||= and a Float key
class G
  def initialize = @c = {1 => 2}
  def add = @c.store(:s, 3)
  def fl = @c[1.5] = 4
  def get = @c
end
g = G.new
g.add
g.fl
p g.get

class H
  def initialize = @c = {"a" => 1}
  def add(k) = @c[k] ||= 9
  def get = @c
end
hh = H.new
hh.add(:z)
hh.add("a")
p hh.get

# a counter with one key class stays as it was
class W
  def initialize
    @counts = Hash.new(0)
    @names = {}
  end
  def see(w) = @counts[w] += 1
  def name(i, s) = @names[i] = s
  attr_reader :counts, :names
end
w = W.new
%w[a b a c a].each { |x| w.see(x) }
w.name(1, "one")
p w.counts, w.names

# every literal assigned to the slot counts: an empty one beside a keyed one
class TwoLiterals
  def initialize = @c = {}
  def reset = @c = {1 => 2}
  def put = @c["x"] = 3
  def c = @c
end
tl = TwoLiterals.new
tl.put
p tl.c
tl.reset
tl.put
p tl.c, tl.c[1], tl.c["x"]
