# A local written from a `<proc>.call(...)` follows the proc's return when that
# return is re-derived late: `r = g.call(e)` kept an sp_IntArray * slot while
# the call answers the boxed poly, and the C compiler refused it (#4330).
g = ->(acc) { acc.push(1) }
e = []
r = g.call(e)
p r
p g.([])
r2 = g.([]); p r2
r3 = g[[]]; p r3
u = ->(acc) { acc.unshift(1) }
r4 = u.call([]); p r4
s = ->(acc) { acc.concat(["x"]) }
r5 = s.call([]); p r5
w = ->(acc) { acc.insert(0, 5) }
r6 = w.call([]); p r6
pr = proc { |acc| acc.append(2) }
r7 = pr.call([]); p r7
ne = [9]
r8 = g.call(ne); p r8
