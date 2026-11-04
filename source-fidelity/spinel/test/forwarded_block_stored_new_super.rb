# A block forwarded out of an inlined method into a constructor that stores it
# (`Register.new(&)`) or into a `super` whose parent stores it. The anonymous
# form read as "no block" and threaded NULL, so the stored block was nil; the
# named form emitted the callee's `lv_blk`, which the splice never declares.

class Register
  def initialize(&handler)
    @handler = handler
  end

  def poke(value) = @handler ? @handler.call(value) : :no_block
end

class Bus
  attr_reader :register

  def install_anon(&) = @register = Register.new(&)
  def install_named(&blk) = @register = Register.new(&blk)
end

class Base
  def on(&handler)
    @handler = handler
  end

  def fire(value) = @handler ? @handler.call(value) : :no_block
end

class AnonSuper < Base
  def on(&) = super(&)
end

class NamedSuper < Base
  def on(&blk) = super(&blk)
end

class ZSuper < Base
  def on(&) = super
end

class ParenSuper < Base
  def on(&) = super()
end

class Recorder
  attr_reader :log

  def initialize
    @log = []
  end

  def wire
    bus = Bus.new
    bus.install_anon { |v| @log << [:new_anon, v] }
    bus.register.poke(1)
    bus.install_named { |v| @log << [:new_named, v] }
    bus.register.poke(2)
    a = AnonSuper.new
    a.on { |v| @log << [:anon_super, v] }
    a.fire(3)
    n = NamedSuper.new
    n.on { |v| @log << [:named_super, v] }
    n.fire(4)
    z = ZSuper.new
    z.on { |v| @log << [:zsuper, v] }
    z.fire(5)
    ps = ParenSuper.new
    ps.on { |v| @log << [:paren_super, v] }
    ps.fire(6)
  end
end

r = Recorder.new
r.wire
r.log.each { |e| p e }

# no block given: the forwarded block is nil, not a stale one
bus = Bus.new
bus.install_anon
p bus.register.poke(0)
z = ZSuper.new
z.on
p z.fire(0)
