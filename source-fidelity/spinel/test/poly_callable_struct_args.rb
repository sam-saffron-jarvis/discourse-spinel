# A callable known only at run time takes its arguments through two channels:
# the legacy sp_int[16] array and the boxed side channel beside it. A value
# whose C representation is a struct (a Time, a Range, a Complex, a Rational,
# a Class) does not convert to sp_int at all, and it reached that array
# verbatim: the C compiler refused the whole program. The boxed publish is
# what carries the real value, so the integer slot takes a placeholder, as a
# Float's already does -- the callable still sees the argument.
def pick(v) = v

t = Time.at(0).utc
cb = pick(->(a, b, c) { "#{a}|#{b.year}|#{c}" })
puts cb.call("x", t, "y")

# first/last read off the boxed range: the Float and String forms answered
# nil there (only the Integer range had an arm), which this is the first
# caller to reach
r = pick(->(a, rng) { "#{a}:#{rng.first}..#{rng.last}" })
puts r.call("n", (1..3))
puts r.call("f", (1.5..2.5))
puts r.call("s", ("a".."c"))

z = pick(->(a, v) { "#{a}:#{v}" })
puts z.call("c", Complex(1, 2))
puts z.call("q", Rational(3, 4))
puts z.call("k", Integer)
puts z.call("d", 2.5)
puts z.call("s", "plain")

# a bound Method in the same slot takes the same path
m = pick(5.method(:+))
puts m.call(3)

# several struct-valued arguments at once, and one after a splat-free mix
many = pick(->(a, b, c, d) { "#{a.year}/#{b.first}/#{c}/#{d}" })
puts many.call(t, (2..4), Rational(1, 2), Complex(0, 1))

# the shape the report hit: an unknown constant's receiver reaches the
# dynamic path with nothing to marshal, and still raises rather than
# failing to build
begin
  f = Nope::Thing.new
  puts f.call("a", Time.now, "b", "c")
rescue NameError => e
  puts e.class
end
