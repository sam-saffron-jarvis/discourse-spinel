# The `<<` arm for a poly receiver hoists the receiver into a C temp, which
# is not a root, evaluates the argument, and dispatches sp_poly_shl. A
# fresh array or string from a method call, or an attribute read on a fresh
# object, is held by nothing else while an allocating argument runs, and a
# local or ivar receiver is held by its slot only until the slot is
# overwritten, by an assignment in the argument, a call in it, an
# interpolation whose to_s assigns it, a comparison whose argument's ==
# assigns it, or the user-defined << the dispatch reaches. On 14ec1cd7 ten
# of the twelve loops below count wrong results under SPINEL_GC_STRESS=1;
# the fixnum receivers cannot be freed. With the temp rooted they print
# twelve zeros and the values CRuby prints.
def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  (1..30).map { |i| i * 3 }
  nil
end

def mk(n)
  return "s#{n}" if n < 0
  return 7 if n == 0
  [1, "a"]
end

class Bag
  attr_reader :items
  def initialize; @items = mk(1); end
end

class Holder
  def initialize; @a = mk(1); end
  def reset; @a = mk(1); 99; end
  def go = @a << (reset; churn; "y")
end

class Tag
  def initialize(h); @h = h; end
  def to_s; @h.reset; churn; "t"; end
end

class Interp
  def initialize; @a = mk(1); @k = Tag.new(self); end
  def reset; @a = mk(1); end
  def go = @a << "x#{@k}"
end

class Eq
  def initialize(h); @h = h; end
  def ==(other); @h.reset; churn; false; end
end

class Compare
  def initialize; @a = mk(1); @k = Eq.new(self); @n = 7; end
  def reset; @a = mk(1); end
  def go = @a << (@n == @k)
end

class Sink
  def initialize(tag, owner); @tag = tag; @owner = owner; end
  def <<(x); @owner.swap; churn; @tag + x; end
end

class Owner
  def pick(n)
    return 7 if n == 0
    Sink.new(n, self)
  end
  def initialize; @s = pick(1); @lit = 0; end
  def swap; @s = pick(2); nil; end
  def go = @s << @lit
end

bad = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
200.times do
  bad[0] += 1 if (mk(1) << (churn; "y")) != [1, "a", "y"]
  bad[1] += 1 if (mk(-1) << (churn; "z")) != "s-1z"
  bad[2] += 1 if (mk(0) << (churn; 2)) != 28
  bad[3] += 1 if (Bag.new.items << (churn; "y")) != [1, "a", "y"]
  r = mk(1) << (churn; "y")
  bad[4] += 1 if r[0] != 1 || r[2] != "y"
  x = mk(1)
  bad[5] += 1 if (x << (x = mk(1); churn; "y")) != [1, "a", "y"]
  bad[6] += 1 if Holder.new.go != [1, "a", "y"]
  bad[7] += 1 if Interp.new.go != [1, "a", "xt"]
  bad[8] += 1 if Compare.new.go != [1, "a", false]
  bad[9] += 1 if ((mk(1) << (churn; "y")) << (churn; "z")) != [1, "a", "y", "z"]
  x = mk(0)
  n = 3
  bad[10] += 1 if (x << n) != 56
  bad[11] += 1 if Owner.new.go != 1
end
p bad

p mk(1) << (churn; "y")
p mk(-1) << (churn; "z")
p mk(0) << (churn; 2)
p Bag.new.items << (churn; "y")
p Holder.new.go
p Interp.new.go
p Compare.new.go
p Owner.new.go
x = mk(0)
n = 3
p x << n
