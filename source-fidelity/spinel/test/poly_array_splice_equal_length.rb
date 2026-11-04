# Equal-length splices into a poly array take an in-place overwrite (#4841);
# the shapes around it: another source kind, a self-splice, a length change.

a = [1, "x", :s, nil, 2.5]
a[1, 2] = [9, 8]
p a
a[0, 2] = a[3, 2]
p a
b = [true, false, true]
b[0, 3] = [1, 2, 3]
p b
c = [nil, nil, nil, nil]
c[1, 2] = ["p", "q"]
c[2, 2] = [1.5, 2.5]
p c
d = [0, "z"]
d[1, 1] = [7, 8, 9]
p d
e = [1, "y", 3]
e[1, 2] = e
p e
f = Array.new(3) { |i| [i, "k"][i % 2] }
f[0, 3] = f
p f
GC.start
p f
