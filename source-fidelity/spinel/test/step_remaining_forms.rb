# The step forms #4779 listed after the boxed-receiver row: the blockless
# Float walk with a boxed limit / step, a step argument of the wrong class
# under a boxed receiver (CRuby's ArgumentError, not a C build error), the
# endless form on a boxed receiver, and a static Bignum receiver, which had
# no arm in either mode. Same answers in both modes; the blockless Integer
# walk on a boxed receiver (an Enumerator) stays out.
f = 2.5; w = 3
p(f.step(9, w).to_a)
v = 1
p((v.step(10, "x") { |i| } rescue $!.class))
p((v.step(10, nil) { |i| break i } rescue $!.class))
p(v.step { |i| break i if i > 3 })
b = 10**25
a = []; b.step(b + 6, 3) { |i| a << i }; p a.size
p a[1]
p((b.step(b - 3, 1) { |i| } rescue $!.class))
c = 10**20
p(c.step(c + 2) { |i| p i })
