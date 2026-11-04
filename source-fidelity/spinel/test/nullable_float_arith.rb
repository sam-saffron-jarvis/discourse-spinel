# A nullable Float slot (an ivar written nil, read through its reader) is
# nil, and nil has no Float arithmetic: the sentinel is a NaN payload the
# hardware carried through every operator, so `nil + 1.0` computed a NaN
# that read back as nil, `nil.nan?` was true, `-nil` flipped the sign bit
# into a NaN that was no longer nil, and `nil.round` was a FloatDomainError.
# Each raises as CRuby does now; nil.to_i and nil.to_f answer nil's own
# values; a real NaN (0.0 / 0.0) is still a Float. The test is emitted only
# where the #3505 marking says a slot can hold the sentinel (#4567).
class R
  def initialize; @f = nil; end
  def f = @f
  def f=(x); @f = x; end
end
r = R.new
r.f = 1.5 if ARGV.length > 5
v = r.f
def t
  yield
rescue NoMethodError, ArgumentError, TypeError => e
  puts "#{e.class}: #{e.message}"
end
t { p v }
t { p v.nil? }
t { p(v + 1.0) }
t { p(v * 2.0) }
t { p(v - 1.0) }
t { p v.nan? }
t { p v.to_s }
t { p [v, 1.0] }
t { p(-v) }
t { p v.abs }
t { p v.round }
t { p v.to_i }
n = 0.0 / 0.0
t { p n.nan? }
t { p n.nil? }
t { p n }
t { p [n].compact }

