# An ivar initialized with a HOMOGENEOUS array literal used to lock its element
# type, and a mismatched push through the reader was silently wrong in one of
# three ways (#4412): the reader handed back a copy so the push went nowhere,
# or the value was coerced, or the C compiler refused an int array being handed
# a `char *`.
#
# One root: widening a typed array to a poly one is a CONVERSION, and a
# conversion of an array is a COPY. That is right on a value the expression
# just made -- which is why pure locals were always correct, they convert the
# LITERAL once -- and wrong on a read of storage the object still holds.
#
# So the ivar widens instead of the read converting. Every arm here is a shape
# the report named, and `equal?` is in them because identity is what a copy
# destroys and a length check would not notice.
require "set"

class Model
  attr_reader :a
  def initialize; @a = ["seed"]; end
end

class Getter
  def initialize; @a = ["seed"]; end
  def a; @a; end          # a hand-written reader must behave as attr_reader does
end

class Empty
  def initialize; @b = []; end
  def b; @b; end          # `[]` defaults to an int array; a String must widen it
end

class Errors
  def initialize; @errors = []; end
  def errors; @errors; end
  def validate; self.errors << "blank"; end   # a push straight through the reader
end

class Mixed
  def initialize; @m = ["seed", 1]; end       # already poly: nothing to widen
  def m; @m; end
end

m = Model.new
e = m.a
puts "attr alias #{e.equal?(m.a)}"
e << 7
puts "attr ivar #{m.a.inspect}"

g = Getter.new
h = g.a
puts "getter alias #{h.equal?(g.a)}"
h << 7
puts "getter ivar #{g.a.inspect}"

n = Empty.new
x = n.b
x << "s"
puts "empty ivar #{n.b.inspect}"

v = Errors.new
v.validate
puts "errors #{v.errors.inspect}"

k = Mixed.new
y = k.m
y << :sym
puts "mixed ivar #{k.m.inspect}"

# a homogeneous ivar that stays homogeneous keeps its typed array: nothing here
# should widen it, and the answer is the check that it still works
class Ints
  def initialize; @i = [1, 2]; end
  def i; @i; end
end
z = Ints.new
z.i << 3
puts "ints #{z.i.inspect} #{z.i.sum}"
