# A receiver passed as a bare C argument is held in a root across the
# argument beside it: cycle(n), each_slice(n), each_cons(n), delete_at(i),
# slice!(i), slice!(i, n) and join(sep). Each argument here allocates
# before the call runs.
class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end

def churn
  (1..60).map { |i| [K.new(i), "s#{i}"] }
  (1..30).map { |i| [i, i.to_s] }
  (1..30).map { |i| i * 2 }
  (1..30).map { |i| "t#{i}" }
  nil
end

def ints = (1..40).map { |i| i * 10 }
def floats = (1..40).map { |i| i * 1.5 }
def strs = (1..40).map { |i| "s#{i}" }
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }
def n5; churn; 5; end
class W
  attr_reader :sep
  def initialize(s); @sep = s; end
end
def ws = [W.new("-"), W.new(1)]

p ints.cycle((churn; 2)).to_a.length
p strs.cycle((churn; 2)).first(3)
p polys.cycle((churn; 2)).to_a.last(2)
p ints.each_slice((churn; 5)).to_a.length
p strs.each_slice((churn; 6)).first
p ints.each_cons((churn; 5)).to_a.length
p ints.delete_at((churn; 5))
p strs.delete_at((churn; -1))
p floats.delete_at((churn; 2))
p polys.delete_at((churn; 1))
p ints.delete_at(n5 > 1 ? 5 : 0)
p strs.join((churn; "-"))[0, 12]
p ints.join("-#{n5}")[0, 12]
p polys.join((churn; ", "))[0, 12]
p ints.delete_at((churn; 50))
p floats.cycle((churn; 2)).to_a.length
p polys.each_slice((churn; 6)).first
p floats.each_cons((churn; 5)).to_a.length
p ints.slice!((churn; 5), 3)
p polys.slice!((churn; 5), 3)
p strs.slice!((churn; 5))
p polys.slice!((churn; 5))
p strs.join((churn; ws[0].sep))[0, 12]
