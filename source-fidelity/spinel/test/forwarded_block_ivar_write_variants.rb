# A block forwarded out of an inlined method (anonymous `&`, a named `&blk`,
# `Proc.new(&blk)`, two levels of forwarding) becomes a proc that runs under
# the self of the code that wrote the block, not the inlined receiver's.

class Register
  def handle(&handler)
    @handler = handler
  end

  def poke(value) = @handler.call(value)
end

class Bus
  attr_reader :register

  def initialize
    @register = Register.new
    @tag = :bus
  end

  def install(&) = @register.handle(&)
  def install_named(&blk) = @register.handle(&blk)
  def install_proc(&blk) = @register.handle(&Proc.new(&blk))
end

class Hub
  attr_reader :bus

  def initialize
    @bus = Bus.new
  end

  def install(&) = @bus.install(&)
end

class Recorder
  attr_reader :log

  def initialize
    @log = []
    @tag = :recorder
  end

  def note(value) = @log << value

  def wire(bus, hub)
    # 1. anonymous `&`: an ivar write and an ivar read
    bus.install { |v| @log << [:anon, @tag, v] }
    bus.register.poke(1)
    # 2. named `&blk`: an implicit-self call resolves against Recorder
    bus.install_named { |v| note([:named, v]) }
    bus.register.poke(2)
    # 3. `Proc.new(&blk)` inside the inlined method
    bus.install_proc { |v| @log << [:proc, v + 100] }
    bus.register.poke(3)
    # 4. forwarded through two inlined methods
    hub.install { |v| @log << [:hub, @tag, v] }
    hub.bus.register.poke(4)
  end
end

r = Recorder.new
r.wire(Bus.new, Hub.new)
r.log.each { |e| p e }

# 5. the stored proc keeps writing to its own object on every call
class Counter
  attr_reader :count

  def initialize(bus)
    @count = 0
    bus.install { |n| @count += n }
  end
end

bus = Bus.new
counter = Counter.new(bus)
bus.register.poke(5)
bus.register.poke(6)
p counter.count
