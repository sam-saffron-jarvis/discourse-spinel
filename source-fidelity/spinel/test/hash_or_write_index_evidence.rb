# An index write into `(@h ||= {})`, or through a zero-argument getter whose
# value is that or-write, is element evidence for @h, as `@h[k] = v` is.
# Without it @h stayed boxed and its `[]=` bound every user-defined `[]=`
# (IdxMem's here) to the written key and value (#4889).
class IdxMem
  def initialize
    @cells = Array.new(8, 0)
  end

  def poke(addr, value)
    @cells[addr] = value
  end

  def []=(addr, value)
    poke(addr, value)
  end

  def [](addr) = @cells[addr]
end

class IdxTraps
  def install(addr, &handler)
    (@traps ||= {})[addr] = handler
  end

  def fire(addr) = (@traps ||= {})[addr].call
end

class IdxLabels
  def label(addr, name) = (@labels ||= {})[addr] = name
  def labels = @labels
end

class IdxBase
  def tbl = (@tbl ||= {})

  def put(k, v)
    tbl[k] = v
    self
  end

  def show = tbl
end

class IdxSub < IdxBase
  def tbl = (@other ||= { x: 1 })
end

class IdxReg
  def self.reg(k, v) = (@reg ||= {})[k] = v
  def self.all = @reg
end

class IdxKeys
  def put
    (@h ||= {})[1] = "a"
    (@h ||= {})["x"] = 2
    @h
  end
end

class IdxMemo
  def get(k) = (@m ||= Hash.new { |h, key| h[key] = key * 2 })[k]
end

class IdxCounter
  def bump(k) = (@c ||= Hash.new(0))[k] += 1
  def c = @c
end

mem = IdxMem.new
mem.poke(1, 7)
mem[2] = 9
traps = IdxTraps.new
traps.install(3) { 42 }
p traps.fire(3)
labels = IdxLabels.new
labels.label(1, "irq")
labels.label(2, "nmi")
p labels.labels
p IdxBase.new.put(1, :one).show
p IdxSub.new.put(:y, 2).show
IdxReg.reg(:a, -> { 1 })
p IdxReg.all[:a].call
p IdxKeys.new.put
p IdxMemo.new.get(21)
counter = IdxCounter.new
counter.bump(:a)
counter.bump(:a)
counter.bump(3)
p counter.c
p mem[1], mem[2]

# A getter with an earlier `return` may hand back another slot, so its
# writes are no evidence for the tail's; the program still answers as CRuby.
class ErHooks
  def initialize(redirect) = @redirect = redirect
  def hooks
    return (@other ||= {}) if @redirect
    (@hooks ||= {})
  end
  def add(k, &blk) = hooks[k] = blk
  def run(k) = hooks[k].call
end
era = ErHooks.new(false); era.add(1) { 10 }
erb = ErHooks.new(true); erb.add(2) { 20 }
p era.run(1), erb.run(2)

# In a class method `tbl` is the class's own getter, not the instance one,
# so the write is no evidence for the instance getter's slot.
class CsTbl
  def tbl = (@a ||= {})
  def self.tbl = (@b ||= {})
  def put(k, v) = tbl[k] = v
  def self.write(k, v) = tbl[k] = v
  def show = @a
  def self.show = @b
end
cs = CsTbl.new
cs.put(1, 2)
CsTbl.write("x", "y")
CsTbl.write(:s, [1])
p cs.show, CsTbl.show, cs.show[1] + 1, CsTbl.show["x"] + "!"

# A subclass overriding the getter answers another slot for the same write,
# so the inherited writer is no evidence for the base getter's slot.
class OvBase
  def tbl = (@a ||= {})
  def put(k, v) = tbl[k] = v
  def show = @a
end
class OvSub < OvBase
  def tbl = (@b ||= {})
  def show_b = @b
end
ovb = OvBase.new
ovb.put(1, 2)
ovs = OvSub.new
ovs.put("x", "y")
ovs.put(:k, 1.5)
p ovb.show, ovs.show, ovs.show_b, ovb.show[1] + 1, ovs.show_b["x"] + "!"
