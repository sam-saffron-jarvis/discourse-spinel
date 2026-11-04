# A multiple assignment with a leading or middle splat over a BOXED scalar
# source: the source stands for itself, `*a, b = x` is `a = [], b = x`. The
# boxed path counted the source as an array of length 0, so the post-splat
# targets read nil and the splat collected nothing; nil stands for itself
# too (`*d = nil` is `[nil]`, the to_ary protocol, not nil.to_a), and a Hash
# is one value, not its pairs.
x = [1, "s"][0]
*a, b = x
p [a, b]
*c, d, e = x
p [c, d, e]
f, *g, h = x
p [f, g, h]
*i = x
p i
n = [nil, 1][0]
*j = n
p j
*k, l = n
p [k, l]
hh = [{ k: 1 }, 2][0]
*m, o = hh
p [m, o.size]
arr = [[1, 2, 3], "s"][0]
*q, r = arr
p [q, r]
