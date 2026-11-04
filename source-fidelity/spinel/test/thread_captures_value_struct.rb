# A by-value struct captured into a Thread or Fiber block. The capture record
# emits a GC scan, and that scan tested the member as a pointer: not valid C
# for a struct, so the build stopped (#4353). None of these types carries a
# pointer the collector must follow, so the capture needs no mark at all.
t0 = Time.now
th = Thread.new { puts (Time.now - t0).class.to_s }
th.join

r = (1..5)
th = Thread.new { puts r.sum.to_s }
th.join

fr = (1.0..5.0)
th = Thread.new { puts fr.first.to_s }
th.join

sr = ("a".."e")
th = Thread.new { puts sr.to_a.join(",") }
th.join

q = Rational(3, 4)
th = Thread.new { puts (q * 2).to_s }
th.join

z = Complex(1, 2)
th = Thread.new { puts z.real.to_s }
th.join

k = String
th = Thread.new { puts k.name }
th.join

# the same capture through a Fiber, which is the other user of the record
start = Time.now
f = Fiber.new { Fiber.yield((Time.now - start).class.to_s) }
puts f.resume

# a value struct alongside a heap capture, so the pointer arm still fires
label = "range is "
rng = (2..4)
th = Thread.new { puts label + rng.sum.to_s }
th.join
