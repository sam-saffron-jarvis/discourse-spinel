# An op-assign on a poly array whose rhs is a typed array of another kind:
# the rhs is boxed to a poly array first, as the binary `m - ["x"]` does.
# The op-assign spelling was refused on a local and emitted C `-` between
# two array pointers on a global or ivar.

$m = [1, "x"]
$m -= ["x"]
p $m
@m = [1, "x"]
@m -= ["x"]
p @m
m = [1, "x"]
m -= ["x"]
p m

# the other set ops and concat, with Integer, String and Float rhs arrays
m = [1, "x"]
m += [2]
p m
m |= ["y", "x"]
p m
m &= [1, 2, "y"]
p m
m += [1.5]
p m
m -= [1.5]
p m

# a boxed rhs that holds an array goes through the run-time set coercion
pairs = [[1], "a"]
m = [1, "a", 3]
m -= pairs[0]
p m
m |= pairs[0]
p m
