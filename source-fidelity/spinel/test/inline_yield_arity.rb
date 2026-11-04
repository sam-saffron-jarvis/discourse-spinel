# an inlined yielding method judges its call's count and keys like any call,
# and binds a **kwrest
def try
  yield
rescue ArgumentError => e
  p e.message
end
def y1(x) = yield(x)
def y(x, k: 1) = yield(x + k)
def y2(a, b = 2) = yield(a + b)
def yr(a, *r) = yield(a, r)
def yk(a, k:) = yield(a + k)
def ykw(a, **kw) = yield(a, kw)
try { y1 { |v| p v } }
try { y1(1, 2) { |v| p v } }
try { y1(5) { |v| p v } }
try { y(1, 2) { |v| p v } }
try { y(1, k: 3) { |v| p v } }
try { y(1, j: 3) { |v| p v } }
try { y2(1) { |v| p v } }
try { y2(1, 2, 3) { |v| p v } }
try { yr { |a, r| p [a, r] } }
try { yr(1, 2, 3) { |a, r| p [a, r] } }
try { yk(1) { |v| p v } }
try { yk(1, k: 2) { |v| p v } }
try { ykw(1, 2) { |a, kw| p [a, kw] } }
try { ykw(1, z: 2) { |a, kw| p [a, kw] } }
def yko(a, k: 1, **o) = yield(a, k, o)
h = {k: 5, q: 6}
try { yko(1, k: 2, z: 3) { |a, k, o| p [a, k, o] } }
try { yko(1, **h) { |a, k, o| p [a, k, o] } }
try { yko(1) { |a, k, o| p [a, k, o] } }
