# Enumerable#min_by, #max_by and #minmax_by are Ruby definitions in
# builtins/enumerable.rb, specialized per call site: typed and boxed
# receivers, hashes, ranges, enumerators, Set, a user class, the count
# form, string, float, array and nil keys, and the blockless Enumerator.
a = [3, 1, 4, 1, 5, 9, 2, 6]
p a.min_by { |x| x }
p a.max_by { |x| x }
p a.min_by { |x| -x }
p a.max_by { |x| (x - 4).abs }
p a.min_by(3) { |x| x }
p a.max_by(3) { |x| x }
p [].min_by { |x| x }
p [].max_by { |x| x }
w = ["pear", "fig", "banana", "kiwi"]
p w.min_by { |s| s.length }
p w.max_by { |s| s.length }
p w.min_by { |s| s }
p w.max_by(2) { |s| s }
p w.min_by { |s| s.length.to_f / 2 }
h = { a: 3, b: 1, c: 2 }
p h.min_by { |k, v| v }
p h.max_by { |k, v| v }
p h.min_by { |pair| pair[1] }
p (1..10).min_by { |i| (i - 5).abs }
p (1..10).max_by { |i| i % 4 }
p a.each_slice(2).min_by { |x, y| x + y }
p a.min_by.each { |x| -x }
e = a.max_by
p e.class
p a.min_by { |x| x.to_s }
p a.max_by { |x| [x % 3, x] }
class Pt
  attr_reader :x, :y
  def initialize(x, y); @x = x; @y = y; end
  def to_s = "(#{x},#{y})"
end
pts = [Pt.new(1, 5), Pt.new(3, 2), Pt.new(0, 9)]
puts pts.min_by { |pt| pt.y }
puts pts.max_by(&:x)
def poly(v) = v
p poly(a).min_by { |x| -x }
p poly(h).max_by { |k, v| v }
p poly(w).min_by(2) { |s| s.length * 2 + (s.start_with?("k") ? 1 : 0) }
p a.min_by { |x| nil }
p a.min_by { |x| x > 4 ? nil : x }.inspect rescue p $!.class
require "set"
p Set[5, 3, 8].min_by { |x| x }
p a.max_by { |x| x.to_f }
p a.minmax_by { |x| x }
p a.minmax_by { |x| -x }
p a.minmax_by { |x| (x - 4).abs }
p [].minmax_by { |x| x }
p [7].minmax_by { |x| x }
w = ["pear", "fig", "banana", "kiwi"]
p w.minmax_by { |s| s.length }
p w.minmax_by { |s| s }
h = { a: 3, b: 1, c: 2 }
p h.minmax_by { |k, v| v }
p (1..10).minmax_by { |i| (i - 5).abs }
p poly(a).minmax_by { |x| x % 4 }
p a.minmax_by.each { |x| -x }
p a.minmax_by { |x| x.to_f }
