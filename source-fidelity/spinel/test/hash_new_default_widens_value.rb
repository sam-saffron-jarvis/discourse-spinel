# The default of `Hash.new(d)` is a value the hash answers, so it is part of
# the value type its `[]=` writes establish. A default of another kind than
# the writes widens the value to poly and is carried boxed. Before, the writes
# alone chose the variant, the string default was handed to the Integer
# constructor, and the C build stopped -- for a local, an ivar, and (with an
# empty container as the default, which infers no element type of its own)
# even for a slot that had already learnt the rule.
a = Hash.new("none"); a["b"] = 1;      p [a["b"], a["zz"], a.sort]
b = Hash.new(0);      b["b"] = "one";  p [b["b"], b["zz"], b.sort]
c = Hash.new([]);     c["b"] = 1;      p [c["b"], c["zz"]]
d = Hash.new({});     d["b"] = 1;      p [d["b"], d["zz"]]
e = Hash.new(0);      e[:s] = "x";     p [e[:s], e[:zz]]
f = Hash.new(0);      f["b"] = 1;      p [f["b"], f["zz"]]     # agreeing kinds stay typed

class K
  def initialize
    @h = Hash.new("none")
    @n = Hash.new(0)
    @a = Hash.new([])
  end
  def go
    @h["b"] = 1
    @n["k"] += 2
    @a["q"] = 3
    [@h["b"], @h["zz"], @n["k"], @n["zz"], @a["q"], @a["zz"]]
  end
end
p K.new.go

$g = Hash.new([]); $g["b"] = 1; p [$g["b"], $g["zz"]]
