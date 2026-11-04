# `k.new(*args)` on a Class value known only at run time spreads the array
# across the chosen class's initialize, as a constant receiver does. The
# positional dispatch arms boxed the whole array as one argument and bound it
# to the first parameter: A([5]) where CRuby says A(5) (#4897).

class A
  def initialize(x) = @x = x
  def to_s = "A(#{@x})"
end

class B
  def initialize(x, y = 9) = (@x = x; @y = y)
  def to_s = "B(#{@x},#{@y.inspect})"
end

class C
  def initialize(x, *ys) = (@x = x; @ys = ys)
  def to_s = "C(#{@x},#{@ys.inspect})"
end

class K
  def initialize(x, k: 0) = (@x = x; @k = k)
  def to_s = "K(#{@x},#{@k})"
end

class P
  def initialize(x, y) = (@x = x; @y = y)
  def to_s = "P(#{@x},#{@y})"
end

# keeps its block as a C parameter: the arm passes the slot
class Q
  def initialize(x, &blk) = (@x = x; @b = blk)
  def to_s = "Q(#{@x},#{@b.nil?})"
end
Q.new(0) { }

S = Struct.new(:x, :y)
D = Data.define(:x)

S.new(1, 2)
B.new(1, 2)

REG = { a: A, b: B, c: C, k: K, p: P, q: Q, s: S, d: D }

def pick(n) = REG[n] == A ? A : REG[n]
def build(n, *args) = pick(n).new(*args)
def fetch_build(n, *args) = REG.fetch(n).new(*args)

# a Class-valued receiver (a method answering a class)
puts build(:a, 5)
puts build(:b, 6)
puts build(:b, 6, 7)
puts build(:b, 6, "s")
puts build(:c, 1)
puts build(:c, 1, 2, 3)
puts build(:q, 4)
v = build(:s, 5)
p v
v = build(:s, 5, "t")
p v
v = build(:d, 7)
p v

# a boxed receiver (read out of a container)
puts fetch_build(:a, 5)
puts fetch_build(:b, 6, nil)
puts fetch_build(:c, 1, 2)
puts fetch_build(:q, 5)
v = fetch_build(:s, 8, 9)
p v
v = fetch_build(:d, 3)
p v

# a literal splat, a splat beside positionals, a splat beside keywords
def lit(n) = pick(n).new(*[5])
puts lit(:a)
puts lit(:b)
def lead(n, *rest) = pick(n).new(1, *rest)
def trail(n, *rest) = pick(n).new(*rest, 2)
puts lead(:p, 5)
puts trail(:p, 7)
def lead_sym(n, *rest) = pick(n).new(:k, *rest)
puts lead_sym(:b)
puts lead_sym(:b, "z")
def kw(n, *args) = pick(n).new(*args, k: 3)
puts kw(:k, 5)

# statement position
$log = []
def stmt(n, *args)
  pick(n).new(*args)
  $log << n
  nil
end
stmt(:a, 1)
stmt(:c, 1, 2)
p $log

# a wrong count is CRuby's ArgumentError, not a bound array
[[:a, [5, 6]], [:b, []], [:s, [1, 2, 3]]].each do |n, args|
  build(n, *args)
  puts "no error"
rescue ArgumentError => e
  puts "#{n}: #{e.message}"
end

# a class answering its own `new` elsewhere in the program leaves the
# others' parameters to the splat all the same
class X
  def self.new(*a) = "X.new(#{a.inspect})"
end
class E
  def initialize(x, y = 9) = (@x = x; @y = y)
  def to_s = "E(#{@x.inspect},#{@y.inspect})"
end
def pick2(i) = i == 0 ? X : (i == 1 ? E : S)
def build2(i, *args) = pick2(i).new(*args)
puts build2(1, 6, "s")
v = build2(2, 5, "t")
p v

# a Struct with its own initialize, a keyword_init Struct, a class with none
T = Struct.new(:x, :y) do
  def initialize(a) = super(a, a * 2)
end
KI = Struct.new(:x, :y, keyword_init: true)
KI.new(x: 1, y: 2)
class N
  def to_s = "N"
end
N.new
def pick3(i) = i == 1 ? T : (i == 2 ? KI : N)
def build3(i, *args) = pick3(i).new(*args)
v = build3(1, 5)
p v
v = build3(2)
p v
puts build3(3)
[[2, [5]], [3, [1]]].each do |i, args|
  build3(i, *args)
  puts "no error"
rescue ArgumentError => e
  puts "#{i}: #{e.message}"
end
p build3(2).x.nil?

# a boxed operand, an Array only at run time; nil spreads to nothing and
# any other value to itself
BOXED = { s: [1, 2], n: [], z: nil, one: "str", big: [1, 2, 3] }
def pick4(i) = i == 0 ? A : (i == 1 ? S : N)
def build4(i, key) = pick4(i).new(*BOXED[key])
v = build4(1, :s)
p v
v = build4(1, :one)
p v
puts build4(2, :n)
puts build4(2, :z)
puts build4(0, :one)
[[1, :big], [2, :one]].each do |i, key|
  build4(i, key)
  puts "no error"
rescue ArgumentError => e
  puts "#{i}: #{e.message}"
end

# a nil or scalar operand: nil spreads to nothing, a scalar to itself
class O
  def initialize(x = 1) = @x = x
  def to_s = "O(#{@x})"
end
def pick5(i) = i == 0 ? O : (i == 1 ? S : N)
REG5 = { o: O, s: S, n: N }
puts pick5(0).new(*nil)
puts pick5(0).new(*5)
v = pick5(1).new(*nil)
p v
v = pick5(1).new(*5)
p v
puts pick5(2).new(*nil)
puts REG5.fetch(:o).new(*nil)
puts REG5.fetch(:o).new(*5)
v = REG5.fetch(:s).new(*nil)
p v
v = REG5.fetch(:s).new(*5)
p v
puts REG5.fetch(:n).new(*nil)
[-> { pick5(2).new(*5) }, -> { REG5.fetch(:n).new(*5) }].each do |f|
  f.call
  puts "no error"
rescue ArgumentError => e
  puts e.message
end

# an anonymous `*` forwarding the method's rest reaches the same arms
S6 = Struct.new(:x, :y)
D6 = Data.define(:a)
class Bare6; end
def build6(k, *) = k.new(*)
p build6(S6, 1, 2).y
p build6([S6, Bare6][ARGV.size], 3, 4).x
p build6(D6, 7).a
p build6(Bare6).class
begin
  build6(Bare6, 1)
rescue ArgumentError => e
  puts e.message
end
