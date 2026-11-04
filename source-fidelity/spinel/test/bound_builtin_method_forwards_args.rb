# A Method over a builtin (`recv.method(:sym)`) binds a synthesized wrapper.
# The wrapper used to take the receiver alone, so an argument passed through
# #call, #[] or #() fell off: `[3, 1, 2].method(:rotate).call(2)` answered
# rotate's default. The wrapper now takes what the call sites pass. (On
# wasm32 the dropped argument was a call-signature trap, which is how it
# surfaced.)
m = [3, 1, 2].method(:rotate)
p m.call(2)
p m[2]
p m.(1)
p "hello world".method(:index).call("o", 5)
p 10.method(:pow).call(2, 7)
sp = "a,b;c".method(:split)
p sp.call(";")
p sp.(",")
p [1, 2, 3].method(:first).call
p [1, 2, 3].method(:first).call(2)
p [4, 5, 6].method(:fetch).call(1)
p method(:Integer).call("ff", 16)
p method(:Integer).call("12")
p method(:Float).call("2.5")
pm = method(:puts)
pm.call("a", "b")
pm.call(1, 2)
q = method(:p)
q.call(:x)
p [1, 2, 3].method(:sum).call
