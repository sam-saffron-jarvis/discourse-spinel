# A literal block handed to a method that forwards it with an anonymous `&`
# to a method that STORES it. The anonymous forwarder is spliced at the call
# site, so the block becomes a proc on the keeper's call -- and its captures
# of enclosing locals need cells, as they do for a named `&blk` forwarder.
# Missing them refused the program ("uncaptured outer variable").

class Keeper
  def install(&handler)
    @handler = handler
  end

  def fire(v) = @handler.call(v)
end

class Box
  attr_accessor :code
end

# 1. Endless-def forwarder, block reads a captured local.
class Front
  attr_reader :keeper

  def initialize
    @keeper = Keeper.new
  end

  def install(&) = keeper.install(&)
  def fire(v) = keeper.fire(v)
end

def run1(front)
  box = Box.new
  front.install { |value| box.code = value }
  3.times { front.fire(7) } until box.code
  box.code
end
p run1(Front.new)

# 2. The block WRITES the captured local: the write must reach the caller.
def run2(front)
  total = 0
  front.install { |value| total += value }
  front.fire(3)
  front.fire(4)
  total
end
p run2(Front.new)

# 3. Two anonymous forwarders in a row before the keeper.
class Outer
  def initialize
    @front = Front.new
  end

  def install(&)
    @front.install(&)
  end

  def fire(v) = @front.fire(v)
end

def run3(outer)
  seen = []
  outer.install { |value| seen << value * 2 }
  outer.fire(5)
  outer.fire(6)
  seen
end
p run3(Outer.new)

# 4. Anonymous forward to a keeper on self.
class SelfKeeper
  def install(&)
    keep(&)
  end

  def keep(&blk)
    @blk = blk
  end

  def fire(v) = @blk.call(v)
end

def run4(k)
  label = "got"
  k.install { |value| label = "#{label} #{value}" }
  k.fire(1)
  k.fire(2)
  label
end
p run4(SelfKeeper.new)
