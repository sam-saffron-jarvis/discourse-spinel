# Comparable#between? and the two-argument Comparable#clamp are written in
# Ruby (builtins/comparable.rb) for a CONCRETE Integer, Bignum or Float
# receiver. The one-argument (Range) clamp, a String receiver and a user
# class with its own `<=>` all stay on the pre-existing C emitters -- see
# the SP_BX_COMPARABLE receiver rule in analyze_desugar.c for the two gaps
# that rule the last two out.

# between?
p 5.between?(1, 10)
p 15.between?(1, 10)
p 5.between?(5, 5)
p 5.between?(6, 10)
p 5.5.between?(1.0, 10.0)
p (2**70).between?(1, 2**80)
p 5.between?(1.0, 10.0)

# clamp, two-argument form
p 5.clamp(1, 10)
p 15.clamp(1, 10)
p (-5).clamp(1, 10)
p 5.clamp(5, 5)
p 5.clamp(1.0, 10.0)
p 15.clamp(1.0, 10.0)
p 5.5.clamp(1.0, 10.0)
p 15.5.clamp(1.0, 10.0)
p 5.5.clamp(1, 10)
p (2**70).clamp(1, 2**80)

# a nil bound is an open side on that end, and the applied bound is
# returned unchanged, so it keeps its own class
p 5.clamp(nil, 3)
p 5.clamp(10, nil)
p 5.clamp(nil, nil)

# the ordering check is STRICT: equal bounds are a valid, empty range
begin
  5.clamp(10, 1)
rescue ArgumentError => e
  puts e.message
end

# an incomparable bound names the failing operand CRuby's way: by VALUE
# for an immediate-ish type, by CLASS NAME for anything else
begin
  5.clamp("a", 10)
rescue ArgumentError => e
  puts e.message
end
begin
  5.clamp(1, "z")
rescue ArgumentError => e
  puts e.message
end
begin
  5.between?("a", 10)
rescue ArgumentError => e
  puts e.message
end
begin
  5.clamp(:sym, 10)
rescue ArgumentError => e
  puts e.message
end
begin
  5.clamp([1, 2], 10)
rescue ArgumentError => e
  puts e.message
end
begin
  5.clamp(1, true)
rescue ArgumentError => e
  puts e.message
end
begin
  (0.0 / 0.0).clamp(1, 10)
rescue ArgumentError => e
  puts e.message
end
begin
  5.clamp(1, 0.0 / 0.0)
rescue ArgumentError => e
  puts e.message
end

# the one-argument Range form is NOT migrated and still answers
p 5.clamp(1..10)
p 15.clamp(1..10)
p (-5).clamp(1..10)
p 15.clamp(..10)
p (-5).clamp(1..)
p 5.5.clamp(1..10)
begin
  5.clamp(1...10)
rescue ArgumentError => e
  puts e.message
end

# a receiver whose slot can carry the nullable-scalar sentinel is nil at
# run time, and nil has neither method
class Holder
  def initialize; @n = nil; end
  def n = @n
  def n=(x); @n = x; end
end
h = Holder.new
h.n = 3 if ARGV.length > 5   # never taken: the slot stays nil
v = h.n
begin
  v.between?(0, 5)
rescue NoMethodError => e
  puts e.message
end
begin
  v.clamp(0, 5)
rescue NoMethodError => e
  puts e.message
end

# a poly receiver keeps the existing runtime dispatch
def poly(x) = x
p poly(5).clamp(1, 10)
p poly(5.5).clamp(1.0, 10.0)
p poly(5).between?(1, 10)
