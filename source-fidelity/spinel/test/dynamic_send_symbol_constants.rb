# A lowered dynamic send compares the name against compile-time symbols and
# reads a boxed Symbol's id directly; a String name is still interned (#4854).
class M
  def initialize = @t = 0
  attr_reader :t
  def op_a = @t += 1
  def op_b = @t += 10
  def run(s) = self.send(s)
end
NAMES = %i[op_a op_b].freeze
WORDS = %w[op_b op_a]
m = M.new
4.times { |i| m.run(NAMES[i % 2]) }
p m.t
2.times { |i| m.run(WORDS[i]) }
p m.t
mixed = [:op_a, "op_b", 3]
2.times { |i| m.run(mixed[i]) }
p m.t
begin
  m.run(:nope)
rescue NoMethodError => e
  p e.class
end
