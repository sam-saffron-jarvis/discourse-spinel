# A user class defining #join, called on a block parameter. The per-class
# dispatch keeps a BUILTIN arm for the array kinds beside the user arms
# (#4071), and that arm passes the call's own argument temp into
# sp_poly_join's `const char *` separator slot. The program that reaches this
# dispatch is precisely the one whose class owns #join -- and its argument is
# whatever that method takes, here another object, so the C did not compile.
#
# The arm is only emitted where the argument could be a separator now. Without
# it the builtin case reaches the raise, which is what CRuby answers for a
# non-String separator anyway.

class Box
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def join(other) = Box.new(@value + other.value)
end

p [Box.new(2), Box.new(3)].map { |b| b.join(Box.new(1)).value }

# a zero-argument user #join keeps its arm, and so does the builtin one
class Tag
  def join = "tag"
end

p [Tag.new].map { |t| t.join }

# Array#join is untouched, including through a poly receiver and with the
# separator absent
p ["a", "b"].join("-")
mixed = [["a", "b"], 1]
p mixed[0].join("-")
p mixed[0].join
p [1, 2].join(", ")
