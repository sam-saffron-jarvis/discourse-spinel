# step with a variable limit / step (boxed under --int-overflow=promote) and a
# block that breaks: the Float arm converts its operands through the Float
# slot, and a numeric iterator's arm answers its receiver boxed even when the
# break widened the inference to poly (#4774). Same answers in both modes.
v = 1; w = 3
v.step(10, w) { |i| p i }
z = 0
r = (v.step(10, z) { |i| break } rescue $!.class); p r
p(v.step(nil, w) { |i| break i if i > 7 })
p(v.step(by: w, to: 10) { |i| p i })
f = 1.5; g = 0.5
f.step(3, g) { |x| p x }
q = (f.step(3, "s") { |x| } rescue $!.class); p q
