# A block forwarded with anonymous `&` through an inlined method into one that
# stores it keeps its own self. The inlined `install` turned the caller's block
# into a proc that captured the Bus (the inlined receiver) as its self, so
# `@code = value` wrote into the Bus and the Recorder still read 0.

class Register
  def initialize
    @handler = nil
  end

  def handle(&handler)
    @handler = handler
  end

  def poke(value) = @handler.call(value)
end

class Bus
  attr_reader :register

  def initialize
    @register = Register.new
  end

  def install(&) = @register.handle(&)
end

class Recorder
  attr_reader :code

  def initialize(bus)
    @code = 0
    bus.install { |value| @code = value }
  end
end

bus = Bus.new
recorder = Recorder.new(bus)
bus.register.poke(7)
puts recorder.code
