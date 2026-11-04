# A class variable is a GC root: an Array held only in @@a (rebound by
# `@@a |= [x]`) was freed and read back overwritten (#4864).
class C
  @@a = [0, 1, 2]
  @@s = "x"
  @@h = {}
  def u(x)
    @@a |= [x]
    @@s = @@s + x.to_s
    @@h[x] = [x] * 2
    nil
  end
  def a = @@a
  def s = @@s
  def h = @@h
end
c = C.new
c.u(4)
c.u(5)
x = (1..200_000).map { |i| [i] * 3 }
p x.size
p c.a
p c.s
p c.h
