# A module method extended into a class is cloned when its body makes a
# receiverless call (a sibling, a bare new), and register_locals had already
# run: a local first assigned in the clone had no slot, so it was never
# declared and every read of it was emitted as nil (#4535, elektronaut).
module ClassMethods
  def add(a, b)
    a.n + b.n
  end
  def blend(a, b)
    one = a
    add(one, b)
  end
  def mk(v)
    one = v
    new(one + 1)
  end
  def twice(a)
    one = a
    add(one, one)
  end
end
class V
  extend ClassMethods
  def initialize(n) = @n = n
  def n = @n
end
p V.blend(V.new(3), V.new(4))
p V.mk(3).n
p V.twice(V.new(5))
