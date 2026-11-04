# `f(*xs)` spreads xs across the argument LIST. Array#product's arms read a
# splat as a single operand array instead, so `[1,2].product(*[])` answered []
# where CRuby answers [[1],[2]], and a non-empty splat nested the operand
# (#4298).
#
# Spreading a runtime-length list needs a variadic helper those arms do not
# have, so a splat they cannot serve is refused at compile time rather than
# answered wrongly. An empty one has an answer here -- no operands at all --
# and that is the shape the report is about.

def count(*args) = args.size

others = []
p count(*others)
p [1, 2, 3].product(*others)
p [1, 2].product(*[])
p %w[a b].product(*others)

# the ordinary forms are unchanged
p [1, 2].product
p [1, 2].product([3])
p [1, 2].product([3], [4])

# a splat into a method's rest parameter was never the broken half
def take(*a) = a
p take(*[])
p take(*[1, 2])
p take(*others)
