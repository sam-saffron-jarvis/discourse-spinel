# An element mutated through a block param reaches the caller's array when the
# container is a method parameter, and when the iterator is one of the
# Ruby-defined builtins (its block param arrives through a yield).
def bang(a) = a.each { |w| w << "#" }
def bang_idx(a)
  a.each_with_index { |w, i| w << i.to_s }
end
def via(a) = bang(a)
def first(a) = a[0] << "1"

ts = [+"x", +"y"]
bang(ts)
p ts
vs = [+"x", +"y"]
bang_idx(vs)
p vs
cs = [+"x", +"y"]
via(cs)
p cs
fs = [+"x", +"y"]
first(fs)
p fs

us = [+"x", +"y"]
us.filter_map { |w| w << "?"; w }
p us
ms = [+"x", +"y"]
r = ms.map { |w| w << "!"; w.size }
p ms, r
ss = [+"x", +"y"]
ss.select { |w| w << "s"; true }
p ss
os = [+"x", +"y"]
os.each_with_object([]) { |w, acc| w << "o"; acc << w }
p os
ns = [+"x", +"y"]
ns.each_with_index { |w, i| w << i.to_s }
p ns

# an Integer array's `<<` is a shift, not an append: the array stays typed
is = [1, 2]
is.each { |x| x << 1 }
p is
# inject's first block param is the memo, not the element
js = [+"a", +"b"]
p js.inject(+"") { |m, w| m << w }
p js
