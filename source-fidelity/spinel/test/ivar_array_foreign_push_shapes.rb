# #4196's continuation (#4210): the push-widening pass ran before the ivar's
# own writes had merged whenever the pushed value's type was already settled
# (a literal, or a local holding one), seeded the UNKNOWN slot with the
# pushed element's own array kind, and the later merge unified two typed
# kinds into the scalar poly box -- where sp_poly_shl coerced the foreign
# element to the boxed array's kind. The pass consults the ivar's direct
# writes first now. The conditional shape widens the aliased SOURCES, so
# the push mutates the receiver's own array, not a rebuilt copy.
class LitPush
  def initialize
    @a = [0]
  end

  def add
    @a.push("one")
  end

  def out = @a
end

h = LitPush.new
h.add
p h.out

class LocalPush
  def initialize
    @a = [0]
  end

  def add
    thing = "one"
    @a.push(thing)
  end

  def out = @a
end

l = LocalPush.new
l.add
p l.out

class ShovePush
  def initialize
    @a = [0]
  end

  def add
    @a << "one"
  end

  def out = @a
end

s = ShovePush.new
s.add
p s.out

class StrTakesInt
  def initialize
    @a = ["s"]
  end

  def add
    @a.push(1)
  end

  def out = @a
end

t = StrTakesInt.new
t.add
p t.out

class SecondWrite
  def initialize
    @a = [0]
  end

  def add
    @a.push("one")
  end

  def add2(x)
    @a.push(x)
  end

  def out = @a
end

w = SecondWrite.new
w.add
w.add2("two")
p w.out

class CondPush
  def initialize
    @a = [0]
    @b = [0]
  end

  def add(thing)
    into = true ? @a : @b
    into.push(thing)
  end

  def out = "a=#{@a.inspect} b=#{@b.inspect}"
end

c = CondPush.new
c.add("one")
puts c.out

# An empty literal keeps taking its element type from the first push.
class EmptyPush
  def initialize
    @a = []
  end

  def add
    @a.push("one")
  end

  def out = @a
end

e = EmptyPush.new
e.add
p e.out

# An int-array ivar pushed only ints keeps its typed representation.
class Narrow
  def initialize
    @n = [1]
  end

  def add
    @n.push(2)
  end

  def out = @n.sum
end

n = Narrow.new
n.add
p n.out
