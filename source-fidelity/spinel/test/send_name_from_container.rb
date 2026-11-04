# `recv.send(name)` with the name read out of a container (`PLAN[i]`,
# `.first`, `.fetch`, `@plan[i]`) lowers like a name from `each` does; it
# was refused, misreported as "undefined method 'send'" (#4850).

class Machine
  attr_reader :total
  PLAN = %i[op_fetch op_read].freeze
  def initialize
    @total = 0
    @plan = [:op_read, :op_fetch]
    @index = 0
  end
  def op_fetch = @total += 1
  def op_read = @total += 10
  def step
    self.send(@plan[@index % 2])
    self.send(PLAN[@index % 2])
    me = self
    me.send(PLAN.first)
    @index += 1
  end
end
PLAN2 = [:op_fetch, :op_read]
WORDS = %w[op_fetch op_read]
HPLAN = { 0 => :op_fetch, 1 => :op_read }
m = Machine.new
[0, 1].each { |i| m.send(PLAN2[i]); m.send(WORDS[i]); m.send(HPLAN.fetch(i)) }
m.send(PLAN2.first)
plan = %i[op_read op_fetch]
m.send(plan[0])
m.step
m.step
p m.total
