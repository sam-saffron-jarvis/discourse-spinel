# A splat spreads across the ARGUMENT LIST, one operand per element, and its
# length is only known at run time: zip handed an array where a value was
# expected and product refused the shape (#4322, #4323).
others = []
p [1, 2].zip(*others)
p [1, 2, 3].product(*others)

built = Array.new(0) { [4, 5] }
p [1, 2, 3].product(*built)

two = [[4, 5], [6, 7]]
p [1, 2].zip(*two)
p [1, 2].product(*two)

one = [[9, 8]]
p [1, 2].zip(*one)
p [1, 2].product(*one)

# mixed: a positional operand alongside the splat
p [1, 2].zip([3, 4], *one)
p [1, 2].product([3], *one)

# a splat of a literal, and a Range operand
p [1, 2].zip(*[[7, 8]])
p [1, 2].zip(*[1..2])

# the shorter operand pads with nil, the longer is cut
p [1, 2, 3].zip(*[[9]])

# no splat at all still takes the tuned arms
p [1, 2].zip([3, 4])
p [1, 2].product([3, 4])
p [1, 2].zip

r = ([1, 2].product(*[3]) rescue $!.class); p r
