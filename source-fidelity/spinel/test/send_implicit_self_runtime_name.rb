# A receiverless `send(name, ...)` / `__send__` with a runtime name in a
# method lowers as `self.send(name, ...)` does, private targets included
# (#4851).

class Cpu
  attr_reader :acc
  PLAN = %i[tick tock].freeze
  def initialize
    @acc = 0
    @plan = PLAN
  end
  def cycle(op) = send(op, 2, 3)
  def step(i) = __send__(@plan[i % 2])
  private
  def adc(addr, value) = @acc += addr + value
  def sta(addr, value) = @acc -= addr * value
  def tick = @acc += 100
  def tock = @acc += 1000
end
c = Cpu.new
c.cycle(:adc)
c.cycle(:sta)
p c.acc
c.step(0)
c.step(1)
p c.acc
