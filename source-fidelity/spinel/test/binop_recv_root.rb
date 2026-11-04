# The receiver of a comparison, and the subject of a case, are bound to a
# temporary before the other side is built. Under SPINEL_GC_STRESS=1 on
# master the other side's allocations collected that temporary, its pool
# slot went to the operand's own object, and twenty-one of the lines below
# came back wrong: `$seen` was `[2, 2]`, `==` answered true and `<` false.
# Each maker allocates enough to trip a stressed collection before its
# object is built; the `Big` maker allocates past the ordinary threshold and
# its `==` is wrong on master with no environment set. The long-name pair
# needs no collector at all: master copied the receiver's C name into a
# 64-byte buffer and cut it to the name of the local above.
require "set"

class Pt
  attr_reader :v
  def initialize(v); @v = v; end
  def ==(o); $seen = [v, o.v]; v == o.v; end
  def self.make(v); $pad = "x" * 3000; new(v); end
end

class Ord
  include Comparable
  attr_reader :v
  def initialize(v); @v = v; end
  def <=>(o); v <=> o.v; end
  def self.make(v); $pad = "x" * 3000; new(v); end
end

class Own
  attr_reader :v
  def initialize(v); @v = v; end
  def <(o); v < o.v; end
  def <=(o); v <= o.v; end
  def self.make(v); $pad = "x" * 3000; new(v); end
end

# a class with its own ==, the receiver a fresh object; != is built from it
p Pt.make(1) == Pt.make(2)
p $seen
p Pt.make(1) != Pt.make(2)
p Pt.make(2) == Pt.make(2)

# Comparable: the operators and between? go through <=>
p Ord.make(1) < Ord.make(2)
p Ord.make(1) >= Ord.make(2)
p Ord.make(1) == Ord.make(2)
p Ord.make(1) != Ord.make(2)
p Ord.make(1).between?(Ord.make(0), Ord.make(2))
p Ord.make(3).between?(Ord.make(1), Ord.make(2))

# the operator defined by the class itself
p Own.make(1) < Own.make(2)
p Own.make(3) <= Own.make(2)

# Set: == and the subset operators are Ruby methods of the prelude
p Set[1, 2] == Set[3]
p Set[Set[3]] == Set[Set[4]]
p Set[1] < Set[1, 2]
p Set[1] <= Set[2]
p Set[1, 2] > Set[3]
p Set[1] >= Set[1]

# a local receiver is read in place; its frame keeps it alive
a = Pt.make(1)
p a == Pt.make(1)
p a != Pt.make(2)
o = Ord.make(1)
p o < Ord.make(2)
p o.between?(Ord.make(0), Ord.make(2))

p Set[1] == Set[2]
p Set[1, 2] == Set[1]

# an operand that allocates past the collection threshold needs no stress
# switch: on master this line answers true with no environment set
class Big
  attr_reader :v
  def initialize(v); @v = v; end
  def ==(o); $seen = [v, o.v]; v == o.v; end
  def self.make(v); $pad = "x" * 4_000_000; new(v); end
end
p Big.make(1) == Big.make(2)
p $seen
p Big.make(1) != Big.make(2)

# a case subject is bound the same way, before the when operands are built
r = case Pt.make(1)
    when Pt.make(2) then "same"
    else "diff"
    end
p r
case Pt.make(3)
when Pt.make(4) then p :same
when Pt.make(3) then p :third
else p :diff
end
p(case Ord.make(2) when Ord.make(1) then :one else :other end)

# the in-place receiver text is no longer copied into a fixed buffer: on master
# the second name, cut to the buffer, read the first local
the_first_operand_of_a_comparison_with_a_deliberately_long_n = Pt.new(2)
the_first_operand_of_a_comparison_with_a_deliberately_long_name = Pt.new(1)
p the_first_operand_of_a_comparison_with_a_deliberately_long_name != Pt.new(2)
p the_first_operand_of_a_comparison_with_a_deliberately_long_name == Pt.new(1)

# a value-type class (never boxed, stored or passed) lives in its temporary and
# needs no root; its comparisons compile and answer as before
class Val
  attr_reader :x
  def initialize(x); @x = x; end
  def ==(o); x == o; end
  def <(o); x < o; end
  def self.mk(n); new(n); end
end
p Val.mk(1) == 1
p Val.mk(1) < 2

# the ordered operators a class defines itself, and <= through <=>, with
# values where reading the operand against itself gives the wrong answer
class Gt
  attr_reader :v
  def initialize(v); @v = v; end
  def >(o); v > o.v; end
  def >=(o); v >= o.v; end
  def self.make(v); $pad = "x" * 3000; new(v); end
end
p Gt.make(1) >= Gt.make(2)
p Gt.make(2) > Gt.make(1)
p Ord.make(3) <= Ord.make(2)
p Set[1, 2] >= Set[1, 3]
