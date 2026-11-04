# A literal block that reads the enclosing method's &block, handed to a method
# that keeps its own block, on a receiver typed only later (an ivar, a local
# assigned from .new). The block becomes a real proc, so the enclosing method
# must keep a real &block too; judged before the receiver's type settled, it
# was inlined instead and the C named a `_cell_handler` nothing declared.
class LiftReg
  def set(&h) = @h = h
  def poke(v) = @h.call(v)
end

class LiftBus
  def install(&handler)
    @reg = LiftReg.new
    @reg.set { |v| handler.call(v) }
  end
  def poke(v) = @reg.poke(v)
end

b = LiftBus.new
b.install { |v| puts v }
b.poke(7)

class LiftLocal
  def install(&handler)
    reg = LiftReg.new
    reg.set { |v| handler.call(v * 2) }
    reg
  end
end
LiftLocal.new.install { |v| p v }.poke(21)

# a callee that only yields still splices, and the handler still runs
class LiftList
  def initialize(xs) = @xs = xs
  def each_item
    @xs.each { |x| yield x }
  end
end
class LiftWalker
  def walk(&handler)
    @list = LiftList.new([1, 2])
    @list.each_item { |v| handler.call(v + 100) }
  end
end
LiftWalker.new.walk { |v| p v }
