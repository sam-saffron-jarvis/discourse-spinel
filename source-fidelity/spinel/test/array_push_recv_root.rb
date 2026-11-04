# The push, << and append arm for an array receiver hoists the receiver
# into a C temp, which is not a root, then evaluates the arguments and
# pushes; its pointer-array form, for an array of typed arrays, does the
# same. A fresh array from a method call or an attribute read is held by
# nothing else while an allocating argument runs, and a local or ivar
# receiver is held by its slot only until an argument overwrites that slot,
# by an assignment, a call, an interpolation whose to_s assigns it, or a
# comparison whose argument's == assigns it. On bc32aa72 this test crashes
# in a plain build and under SPINEL_GC_STRESS=1. With the temp rooted,
# except when the receiver is a slot read and every argument is a number,
# string, symbol, nil, true or false literal, a variable read, self, or a
# builtin array in a variable indexed by an integer, it prints thirteen
# zeros and the lengths CRuby prints; the last loop is that excluded shape,
# a local pushed an index read, and it reads right on both trees.
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
  def go = @a.push((reset; churn; 99)).length
end

class Tag
  def initialize(h); @h = h; end
  def to_s; @h.reset; churn; "t"; end
end

class Interp
  def initialize; @a = strs; @k = Tag.new(self); end
  def reset; @a = strs; end
  def go = @a.push("x#{@k}").length
end

class Eq
  def initialize(h); @h = h; end
  def ==(other); @h.reset; churn; false; end
end

class Compare
  def initialize; @a = polys; @k = Eq.new(self); @n = 7; end
  def reset; @a = polys; end
  def go = @a.push(@n == @k).length
end

class Table
  def initialize; @b = [ints, ints, ints, ints]; end
  def reset; @b = [ints, ints, ints, ints]; nil; end
  def go = @b.push((reset; churn; ints)).length
end

bad = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
200.times do
  bad[0] += 1 if polys.push((churn; 99)).length != 41
  bad[1] += 1 if ints.push((churn; 99)).length != 41
  bad[2] += 1 if floats.append((churn; 1.5)).length != 41
  bad[3] += 1 if (strs << (churn; "z")).length != 41
  bad[4] += 1 if Bag.new.items.push((churn; 99)).length != 41
  bad[5] += 1 if polys.push((churn; 1), (churn; 2)).length != 42
  r = polys.push((churn; 99))
  bad[6] += 1 if r[0] != 10 || r[39] != "s40" || r[40] != 99
  x = ints
  bad[7] += 1 if x.push((x = ints; churn; 99)).length != 41
  bad[8] += 1 if Holder.new.go != 41
  bad[9] += 1 if Interp.new.go != 41
  bad[10] += 1 if Compare.new.go != 41
  bad[11] += 1 if Table.new.go != 5
  x = ints
  y = ints
  bad[12] += 1 if (x << y[3]).length != 41 || x[40] != 40
end
p bad

p polys.push((churn; 99)).last(3)
p ints.push((churn; 99), (churn; 100)).last(3)
p floats.append((churn; 1.5)).last(2)
p (strs << (churn; "z")).last(2)
p Bag.new.items.push((churn; 99)).length
x = ints
p x.push((churn; 99)).length
p x.length
p x.push((x = ints; churn; 99)).length
p x.length
