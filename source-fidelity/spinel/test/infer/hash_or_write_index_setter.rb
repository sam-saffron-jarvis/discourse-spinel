# An index write into `(@h ||= {})`, or through a getter whose value is that
# or-write, types @h like a plain `@h[k] = v` does. It used to leave @h boxed,
# and the boxed `[]=` bound a Proc to OrwMem#[]='s value, widening
# OrwMem#poke's value to untyped as well.
class OrwMem
  def initialize
    @cells = Array.new(4, 0)
  end

  def poke(addr, value)
    @cells[addr] = value
  end

  def []=(addr, value)
    poke(addr, value)
  end

  def [](addr) = @cells[addr]
end

class OrwTraps
  def install(addr, &handler)
    (@traps ||= {})[addr] = handler
  end

  def fire(addr) = @traps[addr].call
end

class OrwHooks
  def hooks = (@hooks ||= {})

  def hook(addr, &blk)
    hooks[addr] = blk
  end

  def run(addr) = hooks[addr].call
end

mem = OrwMem.new
mem.poke(1, 7)
traps = OrwTraps.new
traps.install(3) { 42 }
hooks = OrwHooks.new
hooks.hook(2) { "irq" }
p mem[1], traps.fire(3), hooks.run(2)
