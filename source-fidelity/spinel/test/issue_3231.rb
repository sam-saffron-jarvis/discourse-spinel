def square(x) = x * x
arr = [method(:square)]
m = arr[0]
p m.call(9)
p m.arity
h = { sq: method(:square) }
p h[:sq].call(6)
def g(a, *b) = a
gm = [method(:g)][0]
p gm.arity
# A rest parameter cannot ride the legacy sp_int poly-call cast (the callee's
# trailing rest array has no slot in it); the call takes the per-target thunk
# the bind site stamped instead, which packs the surplus into the rest
# (#4542).
p gm.call(1, 2, 3)
class C
  def dbl(x) = x + x
end
cm = [C.new.method(:dbl)][0]
p cm.call(21)
