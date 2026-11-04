# The numeric predicates on a union-typed receiver. `real?` and `integer?`
# were missing from the poly numeric table, so they raised NoMethodError on a
# receiver that is Integer or Float at run time (#4650). And a class that
# merely DEFINES one of the names below took the poly method dispatch for
# every union-typed number in the program, where a Float or Integer reaching
# the switch had no arm and raised (#4651, the six names #3488 left). The
# switch's default now answers each from the runtime helper the unshadowed
# path uses.
class Unrelated
  def finite? = true
  def infinite? = 1
  def nan? = true
  def abs2 = 0
  def numerator = 7
  def denominator = 7
  def real? = false
  def integer? = false
end

def probe_real(v) = v.real?
def probe_integer(v) = v.integer?
def probe_finite(v) = v.finite?
def probe_infinite(v) = v.infinite?
def probe_nan(v) = v.respond_to?(:nan?) && v.nan?
def probe_abs2(v) = v.abs2
def probe_num(v) = v.numerator
def probe_den(v) = v.denominator

p probe_real(1)
p probe_real(2.5)
p probe_real(2**70)
p probe_integer(1)
p probe_integer(2.5)
p probe_integer(2**70)
p probe_finite(1)
p probe_finite(2.5)
p probe_finite(1.0 / 0.0)
p probe_infinite(1)
p probe_infinite(2.5)
p probe_infinite(1.0 / 0.0)
p probe_infinite(-1.0 / 0.0)
p probe_nan(1)
p probe_nan(2.5)
p probe_nan(0.0 / 0.0)
p probe_abs2(3)
p probe_abs2(-2.5)
p probe_num(3)
p probe_num(Rational(3, 4))
p probe_den(3)
p probe_den(Rational(3, 4))
u = Unrelated.new
p u.finite?
p u.real?
p probe_finite(Unrelated.new)
begin
  probe_real("x")
rescue NoMethodError => e
  puts e.message
end
