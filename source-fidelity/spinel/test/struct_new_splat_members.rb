# `S.new(*args)` next to a construction site that types the members
# Integer. The splat was read as one positional argument, so the members
# kept the Integer type: a String element arriving through the splat was
# unboxed as garbage, and a short array's nil-filled member read as 0.
S = Struct.new(:x, :y)
S.new(1, 2)
def mks(*args) = S.new(*args)
p mks(5)
p mks(5, "t")
# a short Integer array: the unset member is nil, not 0
p S.new(*[7])

# a splat after a leading positional argument
T = Struct.new(:a, :b, :c)
T.new(1, 2, 3)
def mkt(*rest) = T.new(0, *rest)
p mkt
p mkt(:s, 2.5)

# a splat followed by a trailing argument
def mkp(*mid) = T.new(*mid, "end")
p mkp
p mkp(1, [2])

# Data, several members
D = Data.define(:x, :y)
D.new(1, 2)
def mkd(*args) = D.new(*args)
p mkd("a", nil)
p mkd(3, 4)
