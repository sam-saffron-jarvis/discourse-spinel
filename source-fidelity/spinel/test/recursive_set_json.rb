# The same rule, in the two bundled packages that walk containers of their own:
# Set does its walking in Ruby, and JSON answers a cycle the way CRuby's json
# does -- with the nesting limit, not with an identity check.
require "set"
require "json"

st = Set.new
st.add(st)
p st
p st.inspect
p [st].inspect
p st.to_s
begin
  st.flatten
rescue ArgumentError => e
  p e.message
end
p [st.hash == Set.new.hash, st.hash == st.hash, st == st]
p Set[1, 2].inspect
p Set[1, Set[2]].flatten.inspect
s12 = Set[1, 2]
t12 = Set[1, 2]
p s12 == t12

a = []
a << a
begin
  JSON.generate(a)
rescue JSON::NestingError => e
  p [e.class, e.message]
end
begin
  a.to_json
rescue JSON::NestingError => e
  p e.message
end
begin
  JSON.pretty_generate(a)
rescue JSON::NestingError => e
  p e.message
end
h = {}
h[:h] = h
begin
  JSON.generate(h)
rescue JSON::NestingError => e
  p e.message
end
begin
  JSON.pretty_generate(h)
rescue JSON::NestingError => e
  p e.message
end

# the limit is on depth, not on identity: 100 levels serialize, the 101st does not
deep = []
cur = deep
99.times do
  n = []
  cur << n
  cur = n
end
p JSON.generate(deep).size
deeper = []
cur = deeper
100.times do
  n = []
  cur << n
  cur = n
end
begin
  JSON.generate(deeper)
rescue JSON::NestingError => e
  p e.message
end
p JSON.generate([1, { a: 2 }])


# The Set walks keep their frames on the runtime's path, so a raise handled
# inside an outer walk, a retry, or a fiber parked mid-walk leaves nothing
# behind for the next walk
$n = 0
class R
  def inspect
    $n += 1
    raise "x" if $n < 3
    "R"
  end
end
$inner = Set[R.new]
class Mid
  def inspect
    begin
      $inner.inspect
    rescue RuntimeError
      retry
    end
  end
end
p Set[Mid.new].inspect
p $inner.inspect
$fire = true
class B
  def inspect
    if $fire
      $fire = false
      raise "boom"
    end
    "B"
  end
end
$bset = Set[B.new]
class Mid2
  def inspect
    r = nil
    begin
      r = $bset.inspect
    rescue RuntimeError
      r = "rescued"
    end
    r + "/" + $bset.inspect
  end
end
p Set[Mid2.new].inspect
$fire2 = true
class K
  attr_reader :v
  def initialize(v)
    @v = v
  end
  def eql?(o)
    if $fire2
      $fire2 = false
      raise "boom"
    end
    o.is_a?(K) && o.v == @v
  end
  def ==(o)
    eql?(o)
  end
  def hash
    1
  end
end
$x = Set[K.new(1)]
$y = Set[K.new(2)]
$res = []
class Mid3
  def eql?(o)
    begin
      $res << ($x == $y)
    rescue RuntimeError
      $res << :raised
    end
    $res << ($x == $y)
    true
  end
  def ==(o)
    eql?(o)
  end
  def hash
    2
  end
end
m1 = Set[Mid3.new]
m2 = Set[Mid3.new]
p(m1 == m2)
p $res
p($x == $y)
class Y
  def inspect
    Fiber.yield "yielded"
    "Y"
  end
end
f = Fiber.new { Set[Y.new].inspect }
p f.resume
p Set[1, Set[2]].inspect
n1 = Set[Set[3]]
n2 = Set[Set[3]]
p n1 == n2
p Set[Set[3]].flatten.inspect
# a cycle through an Array and a Set
a2 = []
s2 = Set[a2]
a2 << s2
p a2
p s2
p a2 == [s2]
p s2.hash == s2.hash
# a flatten that raised leaves the next one alone
st2 = Set[Set[1]]
st2.add(st2)
begin
  st2.flatten
rescue ArgumentError => e
  p e.message
end
p Set[Set[4], 5].flatten.inspect

# an exit from inside a nested walk abandons it; the at_exit hooks start from
# an empty path and render the very objects the walk was inside. Last in the
# file on purpose: the exit ends the program.
$once = true
class Q
  def inspect
    if $once
      $once = false
      exit
    end
    "Q"
  end
end
Ex = Struct.new(:a)
$ex = Ex.new(Q.new)
$qs = Set[$ex]
$outer = [$qs, { k: 1 }]
at_exit do
  p $outer
  p $qs == Set[$ex]
  p({ k: $ex }.inspect)
end
p $outer
