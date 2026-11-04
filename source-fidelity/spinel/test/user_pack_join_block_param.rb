# A user-defined #pack / #join reached on a block parameter: the builtin arm
# passed the call's own argument into a const char * slot and assigned a
# const char * result into the user class's slot, neither of which compiled
# (#4319).
class Crate
  attr_reader :value
  def initialize(value); @value = value; end
  def pack(other) = Crate.new(@value + other.value)
  def join(other) = Crate.new(@value * other.value)
end
p [Crate.new(2), Crate.new(3)].map { |c| c.pack(Crate.new(1)).value }
p [Crate.new(2), Crate.new(3)].map { |c| c.join(Crate.new(2)).value }
p [Crate.new(2), Crate.new(3)].select { |c| c.pack(Crate.new(1)).value > 3 }.size
[Crate.new(2)].each { |c| p c.pack(Crate.new(1)).value }
p [Crate.new(2), Crate.new(3)].reduce(Crate.new(0)) { |acc, c| acc.pack(c) }.value
p [Crate.new(2), Crate.new(3)].reduce(Crate.new(1)) { |acc, c| acc.join(c) }.value
p Crate.new(2).pack(Crate.new(5)).value
x = Crate.new(4)
p x.join(Crate.new(3)).value
p [1, 2].pack("C*").bytes
p ["a", "b"].join("-")

# a boxed separator / format still reads as a String, and raises when it is not
q = [1, 2]
sep = "-"
p q.join(sep)
r = ([1, 2].join(5) rescue $!.class); p r
