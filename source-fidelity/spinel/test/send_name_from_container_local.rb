# A send name bound to a local first (`step = PLAN[i]; send(step)`) is the
# container element it was read from, and lowers like `send(PLAN[i])`; it was
# refused as a runtime-computed name.

class Machine
  attr_reader :log
  PLAN = %i[op_fetch op_read].freeze
  def initialize
    @log = []
    @plan = [:op_read, :op_fetch]
    @h = { x: :op_fetch, y: :op_read }
    @index = 0
  end
  def op_fetch(*a) = (@log << [:fetch, *a]; 1)
  def op_read(*a) = (@log << [:read, *a]; 10)
  def step
    s = PLAN[@index % 2]
    @index += 1
    self.send(s)
  end
  def forms(i)
    a = PLAN[i]; send(a)
    b = PLAN.first; __send__(b)
    c = PLAN.last; me = self; me.send(c)
    d = PLAN.fetch(i); self.public_send(d)
    e = @plan[i]; send(e)
    f = @h.fetch(i == 0 ? :x : :y); send(f)
    arr = %i[op_read op_fetch]
    g = arr[i]; send(g)
    h = :op_read
    h = PLAN[i]
    send(h, i, 7)
  end
  def sum
    r = 0
    PLAN.size.times { |j| k = PLAN[j]; r += send(k) }
    r
  end
end

m = Machine.new
3.times { m.step }
m.forms(0)
m.forms(1)
p m.sum
[0, 1].each { |i| n = Machine::PLAN[i]; p m.send(n, i) }
p m.log
