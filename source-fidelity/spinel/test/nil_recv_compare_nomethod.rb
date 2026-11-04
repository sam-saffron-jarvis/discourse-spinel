# nil has no `<`, `<=`, `>`, `>=`, `between?` or `clamp`. CRuby answers
# NoMethodError for those. Comparable's ArgumentError -- "comparison of X with
# Y failed" -- is a different complaint: it is what a pair whose `<=>` says nil
# gets, and it belongs to the BOUND being incomparable, not to the receiver
# having no such method.
#
# The typed path already told them apart, from the sentinel test its nilable
# scalar slots carry. A BOXED nil reached the comparison helpers instead and
# was called incomparable: `v > 0` raised the wrong class, and `v.clamp(0, 5)`
# did not raise at all -- it answered nil, which is the one outcome a caller
# cannot tell from a real answer.
class R
  def initialize; @i = nil; end
  def i = @i
  def i=(x); @i = x; end
end
r = R.new
r.i = 3 if ARGV.length > 5     # never taken: the slot stays nil, and stays boxed
v = r.i

[:>, :>=, :<, :<=].each do |op|
  begin
    p v.send(op, 0)
  rescue NoMethodError => e
    puts "#{op}: #{e.message}"
  end
end
begin
  p v.between?(0, 5)
rescue NoMethodError => e
  puts "between?: #{e.message}"
end
begin
  p v.clamp(0, 5)
rescue NoMethodError => e
  puts "clamp: #{e.message}"
end
begin
  p v.clamp(0..5)
rescue NoMethodError => e
  puts "clamp range: #{e.message}"
end

# `<=>` is not a missing method on nil: it answers nil, either way round
p(v <=> 0)
p(0 <=> v)

# nil on the RIGHT keeps the Comparable ArgumentError, which is CRuby's
begin
  p 0 > v
rescue ArgumentError => e
  puts "right-hand nil: #{e.message}"
end

# a real value in the same slot still compares
r2 = R.new
r2.i = 3
w = r2.i
p w > 0, w.between?(0, 5), w.clamp(0, 2)
