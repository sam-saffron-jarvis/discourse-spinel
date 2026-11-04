# An Integer or Float slot that can hold its nil sentinel (an ivar written
# nil, here through the reader) compared with <, >, <=, >=, <=> and between?:
# nil on the left is NoMethodError and nil on the right the Comparable
# ArgumentError, as under CRuby; <=> answers nil either way. Every arithmetic
# helper already tested for the sentinel, but a comparison compared it as a
# number and `nil > 0` answered false. The test is emitted only where the
# #3505 marking says an operand can carry the sentinel, so a loop's `i < n`
# is the bare compare it was (#4567).
class R
  def initialize; @i = nil; @f = nil; end
  def i = @i
  def i=(x); @i = x; end
  def f = @f
  def f=(x); @f = x; end
end
r = R.new
r.i = 3 if ARGV.length > 5
r.f = 1.5 if ARGV.length > 5
v = r.i
w = r.f
def t
  yield
rescue NoMethodError, ArgumentError => e
  puts "#{e.class}: #{e.message}"
end
t { p(v > 0) }
t { p(v <= 0) }
t { p(1 > v) }
t { p(1 <= v) }
t { p(v <=> 0) }
t { p(0 <=> v) }
t { p(v.between?(0, 5)) }
t { p(v.clamp(0, 5)) }
t { p(w > 0.0) }
t { p(w < 1.0) }
t { p(2.0 >= w) }
t { p(w <=> 1.0) }
t { p(v == 0) }
t { p(v == nil) }
t { p(w == nil) }
i = 0
i += 1 while i < 3
p i
t { p(r.i > 1) }
t { p((r.i || 0) > 1) }
