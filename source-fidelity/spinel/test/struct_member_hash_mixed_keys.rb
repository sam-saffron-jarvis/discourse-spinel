# An empty `{}` handed to a Struct constructor is built as the variant the
# member settles on, which writes through the member's reader can widen past
# what the literal alone says.

S = Struct.new(:h)
s = S.new({})
s.h[1] = 2
s.h["x"] = "y"
p s.h

one = S.new({})
one.h[1] = 2
p one.h, one.h[1] + 1

K = Struct.new(:tbl, :n, keyword_init: true)
k = K.new(tbl: {}, n: 0)
k.tbl[:a] = 1
k.tbl["b"] = 2.5
p k.tbl, k.n
