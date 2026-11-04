# A parameter default that calls its own method with that argument omitted
# again is moved into a method of its own, but one that reads the caller's
# block cannot be: the helper would not see the block. Filling it in place
# never terminates, so it is refused rather than crashing the compiler.
def m(x, y = (x > 0 ? m(x - 1) { 1 } + (block_given? ? yield : 0) : 0)) = y + 1
p m(2) { 10 }
