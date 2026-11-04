# Enumerable#filter_map is a Ruby definition in builtins/enumerable.rb,
# specialized per call site: typed and boxed receivers, hashes, ranges,
# enumerators, Set, a user class, nil/false/int/string/float/array block
# values, a named &block forward, the lazy stage and the blockless form.
a = [1, 2, 3, 4, 5, 6]
p a.filter_map { |x| x * 2 if x.even? }
p a.filter_map { |x| x * 10 }
p a.filter_map { |x| x > 3 ? x.to_s : nil }
p a.filter_map { |x| x.odd? && x }
p a.filter_map { |x| x > 100 }
p a.filter_map { |x| nil }
p [].filter_map { |x| x }
w = ["a", "bb", "", "ccc"]
p w.filter_map { |s| s.upcase unless s.empty? }
p w.filter_map { |s| s.length if s.length > 1 }
h = { a: 1, b: 2, c: 3 }
p h.filter_map { |k, v| k if v.odd? }
p h.filter_map { |pair| pair[1] * 2 if pair[1] > 1 }
p (1..10).filter_map { |i| i * i if i % 3 == 0 }
p a.each_slice(2).filter_map { |x, y| x + y if y }
p a.filter_map.each { |x| x if x > 4 }
e = a.filter_map
p e.class
def poly(v) = v
p poly(a).filter_map { |x| x if x > 2 }
p poly(h).filter_map { |k, v| v }
p poly(w).filter_map { |s| s * 2 if s.size == 1 }
class Pt
  attr_reader :x
  def initialize(x); @x = x; end
end
pts = [Pt.new(1), Pt.new(0), Pt.new(3)]
p pts.filter_map { |pt| pt.x if pt.x > 0 }
p pts.filter_map { |pt| pt if pt.x > 0 }.map(&:x)
r = a.filter_map { |x| x * 3 if x < 3 }
p r.sum
p a.filter_map { |x| [x, x] if x < 3 }
p a.filter_map { |x| x.to_f / 2 if x.even? }
require "set"
p Set[1, 2, 3].filter_map { |x| x * 2 if x != 2 }
p a.lazy.filter_map { |x| x * 2 if x.even? }.first(2)
p a.filter_map(&:itself)
def ff(&b) = [1, 2, 3].filter_map(&b)
p ff { |x| x if x != 2 }
p ff { |x| x.to_s if x != 2 }
p a.filter_map { |x| false }
p a.filter_map { |x| x == 2 ? false : x }
p a.filter_map { |x| next if x == 3; x }
p a.filter_map { |x| break :stop if x == 4; x }
