# A hoisted receiver is rooted across the arguments evaluated after it:
# shift(n), pop(n), slice(i, n), [i, n], [range], slice!(range), rotate!(n),
# values_at, fetch_values, and String#insert, #<<, #prepend and #slice!.
# Each argument here allocates before the call runs.
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
def objs = (1..40).map { |i| K.new(i) }
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }
def table = (1..40).to_h { |i| ["k#{i}", i * 10] }
def title = "abcdefghij".dup

p ints.shift((churn; 5))
p floats.shift((churn; 5))
p strs.pop((churn; 5))
p objs.pop((churn; 5)).map(&:v)
p ints.slice((churn; 5), 3)
p strs[(churn; 5), 3]
p polys[(churn; 5), 3]
p ints.values_at((churn; 5), 0)
p polys.values_at((churn; 5), 0)
p ints.fetch_values((churn; 5), 0)
p strs.fetch_values((churn; 5), 0)
p table.values_at((churn; "k5"), "k1")
p table.fetch_values((churn; "k5"), "k1")
p title.insert((churn; 5), "X")
p ints[(churn; 5..7)]
p strs[(churn; 5...8)]
p ints.slice!((churn; 5..7))
p polys.slice!((churn; 5..7))
p strs.rotate!((churn; 5)).first(3)
p polys.rotate!((churn; 5)).first(3)
p(title << (churn; "XY"))
p title.prepend((churn; "XY"), "Z")
p title.slice!((churn; 2))
p title.slice!((churn; 2..4))
begin
  ints.shift((churn; -1))
rescue ArgumentError => e
  puts e.message
end
p ints.slice((churn; 50), 2)
p ints.fetch_values((churn; 5), 40) rescue p $!.class
