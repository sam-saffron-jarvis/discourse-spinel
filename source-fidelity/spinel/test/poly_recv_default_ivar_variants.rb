# A poly-receiver dispatch arm evaluates each class's own default, which
# reads that class's ivars off the cast receiver.

# the default calls a method on the ivar
class Box
  def initialize = @name = "box"
  def tag(x, y = @name.upcase) = "#{x}:#{y}"
end
class Crate < Box
  def initialize = @label = "crate"
  def tag(x, y = @label.length) = "#{x}:#{y}"
end
class Shelf
  def initialize(o) = @o = o
  def go = @o.tag(1)
end
puts Shelf.new(Box.new).go
puts Shelf.new(Crate.new).go

# a three-class hierarchy
class P
  def initialize = @a = 10
  def m(x, y = @a) = x + y
end
class Q < P
  def initialize = @b = 20
  def m(x, y = @b) = x + y
end
class R < Q
  def initialize = @c = 30
  def m(x, y = @c * 2) = x + y
end
class Holder
  def initialize(o) = @o = o
  def go = @o.m(1)
end
p Holder.new(P.new).go
p Holder.new(Q.new).go
p Holder.new(R.new).go

# no required parameter: the zero-argument dispatch arm
class S1
  def initialize = @v = 3
  def n(y = @v) = y
end
class S2 < S1
  def initialize = @w = 4
  def n(y = @w + 1) = y
end
class SHolder
  def initialize(o) = @o = o
  def go = @o.n
end
p SHolder.new(S1.new).go
p SHolder.new(S2.new).go
