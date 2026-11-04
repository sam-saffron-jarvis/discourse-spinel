# A block whose tail is a call to a hand-written setter (#4516): the value
# of `status.interrupt = true` is the right-hand side, as for every
# assignment, not what the writer's body returns. The generic call answered
# the body (a poly here) into a slot inference had typed from the right-hand
# side (a bool), and the C did not compile. A side-effect-free argument is
# re-emitted after the call; any other is bound once to a temporary.
module Badline
  module InstructionSet
    module Flag
      def sei(_addr, _value)
        cycle { status.interrupt = true }
      end
    end

    def execute(name, address, value)
      case name
      when :sei then sei(address, value)
      end
    end
  end

  class Status
    attr_accessor :value

    def initialize = @value = 0

    def interrupt=(enabled)
      self.value = if enabled && enabled != 0
                     0x04
                   end
    end
  end

  class Cycleable
    include InstructionSet
    include InstructionSet::Flag

    attr_accessor :status

    def initialize
      @status = Status.new
      @loop = Fiber.new { loop { main_loop } }
    end

    def cycle! = @loop.resume

    def cycle
      result = yield if block_given?
    end

    def main_loop
      execute(:sei, nil, :lazy)
      Fiber.yield
    end
  end
end

cpu = Badline::Cycleable.new
5.times { cpu.cycle! }
puts "ok"

$n = 0
def next_val = ($n += 1)
class S
  attr_accessor :value, :log
  def initialize = (@value = 0; @log = [])
  def interrupt=(e)
    @log << :set
    self.value = if e && e != 0 then 4 end
  end
  def name=(s)
    @log << s
    :ignored
  end
end
def cyc
  r = yield if block_given?
  r
end
s = S.new
p(cyc { s.interrupt = true })
p s.value
p(cyc { s.interrupt = false })
p s.value
x = (s.name = "a" + "b")
p x
y = (s.interrupt = next_val)
p y
p $n
p s.log
z = s.name = [1, 2].map { |i| i * 2 }.to_s
p z
p s.log.last
s.interrupt = 0
p s.value
