# Regression (#4395): a BoundMethod's "use the self-ful cast" decision cannot
# be `self != NULL`. A receiver VALUE of 0 (Integer 0, false) is stored as
# self == NULL, so a receiver-bound target looked self-less: the self-less cast
# dropped the receiver and shifted every argument by one, so
# `[0.method(:+)][0].to_proc.call(5)` answered a garbage integer and
# `[false.method(:to_s)][0].to_proc.call` answered "true". The bind sites now
# stamp sp_BoundMethod.recv_bound and every cast site (the static Method call,
# the no-user fast path, the shadowed pre-arm, and the `[]` runtime arms)
# selects on it. A top-level method (self-less), a class method (self-less),
# an object-bound method, and a receiverless Kernel wrapper are still correct.

class Handler
  def call(x) = x * 100
end

def top_add(a, b) = a + b

class Obj
  def initialize(v) = @v = v
  def bump(x) = @v + x
end

class Cm
  def self.cm(a) = a + 1
end

# A statically-typed Method (the direct .call path).
m = 0.method(:+)
puts m.call(5)
f = false.method(:to_s)
puts f.call

# A Method in a poly slot with NO user class defining call (the fast path).
puts [0.method(:+)][0].to_proc.call(5)
puts [0.method(:+)][0][5]
puts [false.method(:to_s)][0].to_proc.call

# A Method sharing a poly slot with a user class that defines call (the
# shadowed pre-arm).
puts [0.method(:+), Handler.new][0].call(5)
puts [false.method(:to_s), Handler.new][0].to_proc.call

# A non-zero value receiver already rode the self-ful cast; keep it working.
puts 1.method(:+).call(5)
puts [1.method(:+), Handler.new][0].call(5)

# Self-less targets must stay self-less: a top-level method has no self slot.
puts [method(:top_add)][0].to_proc.call(1, 2)
puts [method(:top_add), Handler.new][0].call(3, 4)

# An object-bound method, a class method, and a receiverless Kernel wrapper.
o = Obj.new(100)
puts [o.method(:bump), Handler.new][0].call(5)
puts [Cm.method(:cm)][0].call(9)
puts [method(:String)][0].call(123).inspect
