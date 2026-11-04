# `recv[key] op= v` on a boxed receiver with a Symbol or String key read the
# element as an Integer whatever it held: a Float element came back as its
# raw bits, and a String element did not compile.

def pick(x) = x

h = pick(1) == 1 ? { a: 1.5, b: "s", c: 2 } : [1]
h[:a] += 1
h[:b] += "t"
h[:c] *= 3
h[:a] *= 2
p h

g = pick(1) == 1 ? { "k" => "x" } : [1]
g["k"] += "y"
p g
