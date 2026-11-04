# Enumerable#flat_map (and its alias collect_concat) is a Ruby definition in
# builtins/enumerable.rb, specialized per call site. `if v.is_a?(Array)` on
# the typed block value is decided at compile time (fold_static_is_a), so an
# Array answer concatenates into a typed result and a scalar one appends;
# a boxed value keeps the run-time test. Also: nil and Hash answers are
# appended as they are, a `next []`, a named &block forward, Set, a user
# class, boxed receivers and the lazy stage.
a = [1, 2, 3]
p a.flat_map { |x| [x, x * 10] }
p a.flat_map { |x| x * 10 }
p a.flat_map { |x| [x.to_s, "!"] }
p a.flat_map { |x| x.to_s }
p a.flat_map { |x| [x.to_f] }
p a.flat_map { |x| [[x]] }
p a.flat_map { |x| [x, x] if x.odd? }
p a.flat_map { |x| x.odd? ? [x, x] : x }
p a.flat_map { |x| x.odd? ? [x, x] : nil }
p a.flat_map { |x| { x => 1 } }
p a.flat_map { |x| [] }
p [].flat_map { |x| [x] }
h = { a: 1, b: 2 }
p h.flat_map { |k, v| [k, v] }
p h.flat_map { |pair| pair }
p h.flat_map { |k, v| v }
p (1..3).flat_map { |i| [i] * i }
p a.each_slice(2).flat_map { |x, y| [x, y] }
p a.flat_map.each { |x| [x, -x] }
p a.collect_concat { |x| [x, x] }
def poly(v) = v
p poly(a).flat_map { |x| [x, x * 2] }
p poly(a).flat_map { |x| x > 1 ? [x] : x }
p poly(h).flat_map { |k, v| [k] * v }
w = %w[a bb]
p w.flat_map { |s| s.chars }
p w.flat_map(&:chars)
class Pt
  attr_reader :x
  def initialize(x); @x = x; end
end
pts = [Pt.new(1), Pt.new(2)]
p pts.flat_map { |pt| [pt.x, pt.x * 2] }
p pts.flat_map { |pt| [pt] }.map(&:x)
p pts.flat_map { |pt| pt }.map(&:x)
require "set"
p Set[1, 2].flat_map { |x| [x, x] }
def fl(&b) = [1, 2].flat_map(&b)
p fl { |x| [x, x] }
p fl { |x| x.to_s }
r = a.flat_map { |x| [x, x] }
p r.sum
p a.flat_map { |x| next [] if x == 2; [x] }
nested = [[1, 2], [3]]
p nested.flat_map { |xs| xs }
p nested.flat_map { |xs| xs.map { |y| y * 2 } }
p a.lazy.flat_map { |x| [x, x] }.first(3)
