# The unshift and prepend arms for an array receiver hoist the receiver
# into a C temp, which is not a root, then evaluate the arguments and
# insert them at the front; the poly-array arm roots each boxed argument
# but not the receiver, the typed arm roots nothing. A fresh array from a
# method call or an attribute read is held by nothing else while an
# allocating argument runs, and a local or ivar receiver is held by its
# slot only until an argument overwrites that slot, by an assignment, a
# call, an interpolation whose to_s assigns it, or a comparison whose
# argument's == assigns it. On 7a25048f this test crashes in a plain build
# and under SPINEL_GC_STRESS=1. With the temp rooted, except when the
# receiver is a slot read and every argument is a number, string, symbol,
# nil, true or false literal, a variable read, self, or a builtin array in
# a variable indexed by an integer, it prints twelve zeros and the values
# CRuby prints; the last loop is that excluded shape, a local given an
# index read, and it reads right on both trees.
class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end

def churn
  (1..60).map { |i| [K.new(i), "s#{i}"] }
  (1..30).map { |i| [i, i.to_s] }
  (1..30).map { |i| i * 2 }
  (1..30).map { |i| "t#{i}" }
  nil
end

def ints = (1..40).map { |i| i * 10 }
def floats = (1..40).map { |i| i * 1.5 }
def strs = (1..40).map { |i| "s#{i}" }
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }

class Bag
  attr_reader :items
  def initialize; @items = (1..40).map { |i| i * 10 }; end
end

class Holder
  def initialize; @a = ints; end
  def reset; @a = ints; 99; end
  def go = @a.unshift((reset; churn; 99)).length
end

class Tag
  def initialize(h); @h = h; end
  def to_s; @h.reset; churn; "t"; end
end

class Interp
  def initialize; @a = strs; @k = Tag.new(self); end
  def reset; @a = strs; end
  def go = @a.prepend("x#{@k}").length
end

class Eq
  def initialize(h); @h = h; end
  def ==(other); @h.reset; churn; false; end
end

class Compare
  def initialize; @a = polys; @k = Eq.new(self); @n = 7; end
  def reset; @a = polys; end
  def go = @a.unshift(@n == @k).length
end

bad = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
200.times do
  bad[0] += 1 if polys.unshift((churn; 99)).length != 41
  bad[1] += 1 if ints.unshift((churn; 99)).length != 41
  bad[2] += 1 if floats.prepend((churn; 1.5)).length != 41
  bad[3] += 1 if strs.unshift((churn; "z")).length != 41
  bad[4] += 1 if Bag.new.items.prepend((churn; 99)).length != 41
  bad[5] += 1 if polys.unshift((churn; 1), (churn; 2)).length != 42
  r = polys.unshift((churn; 99))
  bad[6] += 1 if r[0] != 99 || r[1] != 10 || r[40] != "s40"
  x = ints
  bad[7] += 1 if x.unshift((x = ints; churn; 99)).length != 41
  bad[8] += 1 if Holder.new.go != 41
  bad[9] += 1 if Interp.new.go != 41
  bad[10] += 1 if Compare.new.go != 41
  x = ints
  y = ints
  bad[11] += 1 if x.unshift(y[3]).length != 41 || x[0] != 40
end
p bad

p polys.unshift((churn; 99)).first(3)
p ints.unshift((churn; 99), (churn; 100)).first(3)
p floats.prepend((churn; 1.5), (churn; 2.5)).first(3)
p strs.unshift((churn; "y"), (churn; "z")).first(3)
p Bag.new.items.prepend((churn; 99)).length
x = ints
p x.unshift((churn; 99)).length
p x.length
p x.unshift((x = ints; churn; 99)).length
p x.length
