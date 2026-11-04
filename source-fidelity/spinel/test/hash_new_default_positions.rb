# `Hash.new(default)` has no element types of its own: the variant is decided
# by what is written into it. Two positions had nothing to decide from and
# emitted the "undefined method 'new' for class Hash" refusal instead (#4291).
#
# A method's VALUE: `def mk = Hash.new(0)` has no receiver use, so inference
# left it unknown and the method emitted as void.
#
# An IVAR write: the slot was already typed from the later `@h[k]` uses -- the
# C struct held the right hash -- while the Hash.new node itself stayed
# unknown, so the constructor refused to build what the slot expected.
#
# (Hash#inspect is avoided here: its spacing differs between ruby versions.)

class Counter
  def initialize
    @counts = Hash.new(0)
  end

  def bump(key)
    @counts[key] += 1
    @counts
  end
end

p Counter.new.bump(:a)[:a]

c = Counter.new
c.bump(:a)
c.bump(:a)
c.bump(:b)
p [c.bump(:a)[:a], c.bump(:b)[:b]]
p c.bump(:a).size

def mk = Hash.new(0)
p mk.size
p mk[:missing]

def mk_plain = Hash.new
p mk_plain.size
p mk_plain[:missing].nil?

# the positions that already worked
x = Hash.new(0)
x[:k] += 2
p x[:k]
p x.size

class Holder
  def initialize
    @h = Hash.new("none")
  end

  def get(k) = @h[k]
  def put(k, v)
    @h[k] = v
    @h
  end
end

h = Holder.new
p h.get("absent")
p h.put("a", "b")["a"]
p h.get("still absent")

# The tail-position rule fills in a type where inference had none; it must not
# override one the CALLERS already narrowed. `str_hash` here is Hash[String,
# String] from the writes below, and answering the widest variant for it
# re-emitted every such helper as a poly hash (#4304).
def str_hash
  Hash.new("")
end

sh = str_hash
sh["k"] = "v"
p sh["k"].upcase
p sh["missing"].length
p sh.size

def int_hash
  Hash.new(0)
end

ih = int_hash
ih["n"] = 3
p ih["n"] + ih["absent"]
