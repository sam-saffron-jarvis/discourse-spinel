# A boxed Array's each read its length once before the loop, so a block
# that shrinks the receiver walked on past the new end and yielded nils
# (`[1, nil, nil]` for a block that clears the array), and one that grows
# it was not followed. The typed loops read the length every turn; the
# boxed one does now too. Every Ruby-defined Enumerable method walks a
# boxed receiver through this loop.
def poly(v) = v
poly("s")
a = poly([1, 2, 3])
seen = []
a.each { |x| seen << x; a.clear }
p seen
b = poly([1, 2, 3])
seen2 = []
b.each { |x| seen2 << x; b.pop }
p seen2
c = poly([1, 2, 3])
p c.count { |x| c.clear; true }
g = poly([1, 2])
sg = []
g.each { |x| sg << x; g << x + 10 if g.size < 4 }
p sg
h = poly({ a: 1, b: 2 })
sh = []
h.each { |k, v| sh << k; h.delete(:b) }
p sh
