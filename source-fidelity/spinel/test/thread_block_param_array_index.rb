# The first parameter of a Thread.new / Fiber.new block is a plain value, not
# the &block the body calls through: `ab[1]` used to be read as a call of the
# block itself, splicing the body into its own body with ab rebound to 1.
lo = 3
hi = 7
t = Thread.new([lo, hi]) { |ab| ab[1] - ab[0] }
p t.value
t2 = Thread.new([1, 2, 3]) { |xs| xs.length }
p t2.value
f = Fiber.new { |a| Fiber.yield a[0]; a[1] }
p f.resume([10, 20])
p f.resume
# a real &block called from inside a thread body still reaches the block
def run(&blk)
  t = Thread.new { blk.call(5) }
  t.value
end
p run { |x| x * 2 }
def run2
  t = Thread.new { yield 7 }
  t.value
end
p run2 { |x| x + 1 }
e = Enumerator.new { |y| y << 1; y << 2 }
p e.to_a
