# A multiple assignment builds each value into a temporary before any target
# takes one, so a value that is a fresh object is held by nothing while the
# values after it are built: a collection a later value's build ran swept it.
# Its targets' receivers and indexes were evaluated at each store, after the
# values, where Ruby evaluates them first, left to right, so a call in a
# target ran after the values, a key evaluated in Ruby's order is a fresh
# object held by nothing while the values build, and a frozen hash target was
# written without complaint. Covers two and three values into locals, instance
# and global variables; index targets with a built key on String-keyed hashes
# with Integer, String and poly values, Integer- and Symbol-keyed hashes, the
# general hash, an Array and a container typed at run time; attribute targets
# whose receiver is a call, evaluated once; a splat and a nested target; a
# value that drops the only other holder of an earlier one; the assignment as
# a value; the order of the targets' receivers and keys against the values, a
# value built in the statement's prelude among them, and a target assigned
# before a later target's plain index, a nested target among them; the
# assignment's own stores collecting, through a hash hook, what a target's
# index cleared, an earlier target dropped, or a value held by a global alone;
# the to_s an interpolation runs clearing the holder of a hoisted receiver, a
# hoisted key and a value; a Bignum literal, which is built, an interpolated
# Symbol, a lambda and the last match, which allocate, a store that boxes a
# Process.times, and the receiver before an index built in the prelude; a
# store that boxes a Range into a poly slot; a swap through plain indexes; and
# a frozen hash, and a frozen object under an attribute or instance variable
# target, refused after the values are built, as CRuby refuses them. Each
# collecting builder collects the object heap outright and allocates past the
# string heap's own trigger. The order sections, the swap and the Range store
# have nothing to sweep; they hold the emitter to the shape.
def gcv(i)
  GC.start
  ("pad" * 150_000).size
  "v#{i}"
end
def gci(i)
  GC.start
  ("pad" * 150_000).size
  i * 2
end

bad = 0
60.times do |i|
  a, b = "x#{i}", gcv(i)
  bad += 1 unless a == "x#{i}" && b == "v#{i}"
  a, b, c = "x#{i}", "y#{i}", gcv(i)
  bad += 1 unless a == "x#{i}" && b == "y#{i}" && c == "v#{i}"
  a, b = [i, i + 1], gcv(i)
  bad += 1 unless a == [i, i + 1] && b == "v#{i}"
  a, b = {"k" => i}, gci(i)
  bad += 1 unless a == {"k" => i} && b == i * 2
end
p bad

class Pair
  attr_accessor :x, :y
  def initialize; @x = "a"; @y = "b"; end
  def fill(i)
    @x, @y = "x#{i}", gcv(i)
  end
  def fill_gv(i)
    $gx, $gy = "x#{i}", gcv(i)
  end
end
$gx = nil
$gy = nil
pr = Pair.new
bad = 0
60.times do |i|
  pr.fill(i)
  bad += 1 unless pr.x == "x#{i}" && pr.y == "v#{i}"
  pr.fill_gv(i)
  bad += 1 unless $gx == "x#{i}" && $gy == "v#{i}"
end
p bad

# index targets with a key that is a fresh object, on each hash kind
ss = {"a" => "b"}
60.times { |i| ss["k#{i}"], ss["m#{i}"] = "x#{i}", gcv(i) }
p ss.size, ss.keys.uniq.size, ss["k50"], ss["m50"]
si = {"a" => 1}
60.times { |i| si["k#{i}"], si["m#{i}"] = i, gci(i) }
p si.size, si.keys.uniq.size, si["k50"], si["m50"]
is = {1 => "a"}
60.times { |i| is[gci(i) + 1000], is[gci(i) + 2000] = "x#{i}", gcv(i) }
p is.size, is[1100], is[2100]
sp = {"a" => 1, "b" => "x"}
60.times { |i| sp["k#{i}"], sp["m#{i}"] = "x#{i}", gci(i) }
p sp.size, sp.keys.uniq.size, sp["k50"], sp["m50"]
yp = {a: 1, b: "x"}
60.times { |i| yp[i.even? ? :k0 : :k1], yp[:k2] = "x#{i}", gcv(i) }
p yp.size, yp.keys.uniq.size, yp[:k0], yp[:k1], yp[:k2]
gp = {"a" => 1, :b => 2}
60.times { |i| gp["k#{i}"], gp[[i]] = "x#{i}", gcv(i) }
p gp.size, gp.keys.uniq.size, gp["k50"], gp[[50]]
arr = Array.new(10, "z")
60.times { |i| arr[gci(i) % 10], arr[(gci(i) + 1) % 10] = "x#{i}", gcv(i) }
p arr.size, arr.uniq.size, arr[0], arr[1]

# a container typed at run time stores after the values are built
def put(x, i)
  x[i % 10], x[(i + 1) % 10] = "a#{i}", gcv(i)
end
def check(x)
  bad = 0
  x.each_with_index { |v, i| bad += 1 unless v == "a#{i}" || v == "a#{i + 190}" || v.start_with?("v") }
  bad
end
def put2(x, i)
  x[gci(i) % 10], x[(i + 1) % 10] = "a#{i}", gcv(i)
end
pa = Array.new(10, "z")
pb = Array.new(10) { nil }
60.times { |i| put(pa, i); put(pb, i) }
p pa.size, check(pa), pa[0], pa[1], pb.size, check(pb), pb[0], pb[1]
pc = Array.new(10, "z")
pd = Array.new(10) { nil }
100.times { |i| put2(pc, i); put2(pd, i) }
p pc.size, pc.count { |v| v.start_with?("a") || v.start_with?("v") }, pd.size, pd.compact.size

# a store that boxes a by-value struct into a poly slot allocates
bs = {"a" => 1, "b" => "x"}
bad = 0
60.times do |i|
  bs["r"], t = (i..i + 1), "t#{i}"
  bad += 1 unless bs["r"] == (i..i + 1) && t == "t#{i}"
end
p bad

# attribute targets whose receiver is a call
$n = 0
def mk; $n += 1; $pr; end
$pr = Pair.new
60.times { |i| mk.x, mk.y = "x#{i}", gcv(i) }
p $n, $pr.x, $pr.y

# a splat and a nested target
def pair(i); ["x#{i}", "y#{i}"]; end
bad = 0
60.times do |i|
  a, *r = "x#{i}", gcv(i), "z#{i}"
  bad += 1 unless a == "x#{i}" && r == ["v#{i}", "z#{i}"]
  a, *r, z = "x#{i}", gcv(i), "z#{i}"
  bad += 1 unless a == "x#{i}" && r == ["v#{i}"] && z == "z#{i}"
  (a, b), c = pair(i), gcv(i)
  bad += 1 unless a == "x#{i}" && b == "y#{i}" && c == "v#{i}"
end
p bad

# a value that drops the only other holder of an earlier one
bad = 0
60.times do |i|
  $s = "keep#{i}"
  a, b = $s, ($s = nil; gcv(i))
  bad += 1 unless a == "keep#{i}" && b == "v#{i}"
end
p bad

# the assignment as a value
bad = 0
60.times do |i|
  r = (a, b = "x#{i}", gcv(i))
  bad += 1 unless r == ["x#{i}", "v#{i}"] && a == "x#{i}"
end
p bad

# the targets' receivers and keys are evaluated before the values, left to
# right, and a receiver that is a call is evaluated once
def k(n); puts "key #{n}"; n; end
def v(n); puts "value #{n}"; n; end
$h = {1 => 0}
def r(n); puts "receiver #{n}"; $h; end
r(1)[k(1)], r(2)[k(2)] = v(1), v(2)
p $h
ia = [0, 0]
ia[k(0)], ia[k(1)] = v(3), v(4)
p ia
def o(n); puts "object #{n}"; $pr; end
o(1).x, o(2).y = v(5).to_s, v(6).to_s
p $pr.x, $pr.y
$n = 0
mk.x, mk.y = "p", "q"
p $n
# a value that is built in the statement's prelude, a literal, still comes
# after the targets' parts, and a target assigned earlier does not reach a
# later target's plain index
pl = [nil, nil]
pl[k(0)], x = [v(9), v(10)], v(11)
p pl, x
ib = [0, 0, 0]
i = 2
i, ib[i] = 0, 7
p i, ib

# the assignment's own stores can collect: a key held only by a global that
# a later target's index clears, a receiver an earlier target's assignment
# drops before a store that runs a hash hook, and a value held only by a
# global the hook clears
class KH
  attr_reader :i
  def initialize(i); @i = i; end
  def hash; $s = nil; GC.start; ("pad" * 150_000).size; @i; end
  def eql?(o); o.is_a?(KH) && o.i == @i; end
end
def clearer(i); $k = nil; GC.start; ("pad" * 150_000).size; i % 3; end
$k = ""
$s = ""
h1 = {"a" => 1}
h2 = {0 => 0}
60.times { |i| $k = "key#{i}"; h1[$k], h2[clearer(i)] = 1, 2 }
p h1.size, h1.keys.count { |s| s.start_with?("key") }, h2.size
ks = Array.new(200) { |i| KH.new(i) }
gh = {KH.new(-1) => 0}
def mk3; [1, 2, 3]; end
bad = 0
60.times do |i|
  a = mk3
  a, gh[ks[i]], a[0] = [7, 8, 9], 1, 99
  bad += 1 unless a == [7, 8, 9]
end
p gh.size, bad
out = []
60.times { |i| $s = "val#{i}"; gh[ks[i]], t = 1, $s; out << t }
p gh.size, out.count { |s| s.start_with?("val") }

# user code no predicate sees: the to_s an interpolation runs clears the
# only other holder of a hoisted receiver, of a hoisted key, and of a value
class Box
  attr_accessor :v
  def initialize(v); @v = v; end
end
class Killer
  def to_s; $b = nil; $k = nil; $g = nil; GC.start; ("pad" * 150_000).size; "t"; end
end
$kk = Killer.new
$pool = []
th = {"z" => "zz"}
60.times do |i|
  $b = Box.new("b#{i}")
  $b.v, th["x#{$kk}#{i}"] = "w#{i}", "hv#{i}"
  $pool << Box.new("pool")
end
p th.size, $pool.count { |x| x.v == "pool" }
t1 = {"z" => "zz"}
t2 = {"z" => "zz"}
60.times { |i| $k = "key#{i}"; t1[$k], t2["x#{$kk}#{i}"] = "v#{i}", "w#{i}" }
p t1.size, t1.keys.count { |s| s.start_with?("key") }, t2.size
out = []
60.times { |i| $g = "g#{i}"; a, b = $g, "wrap#{$kk}"; out << a }
p out.count { |s| s.is_a?(String) && s.start_with?("g") }

# a value that is a Bignum literal is built, unlike the other literals; a
# later value that is an interpolated Symbol allocates
bad = 0
60.times do |i|
  a, b = 123456789012345678901234567890, gcv(i)
  bad += 1 unless a == 123456789012345678901234567890 && b == "v#{i}"
  a, b = "x#{i}", :"sym#{i}"
  bad += 1 unless a == "x#{i}" && b == :"sym#{i}"
end
p bad

# a later value that is a lambda allocates its Proc, and one that is the
# last match builds its MatchData; a store that boxes a Process.times
# allocates
bad = 0
pt = Array.new(4) { nil }
60.times do |i|
  a, b = "x#{i}", -> { i }
  bad += 1 unless a == "x#{i}" && b.call == i
  subject = "a#{i}b"
  subject =~ /b/
  a, m = "x#{i}", $~
  bad += 1 unless a == "x#{i}" && m[0] == "b"
  pt[0], s = Process.times, "t#{i}"
  bad += 1 unless pt[0].class == Process::Tms && s == "t#{i}"
end
p bad

# within one target the receiver runs before an index built in the prelude
$gh = {[1] => 0}
def gr(n); puts "receiver #{n}"; $gh; end
gr(1)[[k(1)]], x = v(1), v(2)
p $gh, x

# a nested target assigned before a later target's index
na = [0, 0, 0, 0]
ni = 3
(ni, nj), na[ni] = [1, 5], 2
p ni, nj, na

# a swap through plain indexes
sw = %w[a b c d]
sw[0], sw[3] = sw[3], sw[0]
p sw
sw[1], sw[2] = sw[2], sw[1]
p sw

# a frozen hash is refused after the values are built, and the value's
# side effects have run
fz = {"a" => 1}.freeze
x = nil
begin
  fz[k(7).to_s], x = v(7), v(8)
rescue FrozenError => e
  p e.class
end
p fz, x
# and a frozen object refused by an attribute target and by an instance
# variable target
fo = Pair.new.freeze
begin
  fo.x, x = "p", 9
rescue FrozenError => e
  p e.class
end
p fo.x, x
begin
  fo.fill(1)
rescue FrozenError => e
  p e.class
end
p fo.y
