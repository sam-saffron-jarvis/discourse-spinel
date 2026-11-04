# Enumerable#take_while and #drop_while are Ruby definitions in
# builtins/enumerable.rb, specialized per call site: typed and boxed
# receivers, hashes, ranges (an endless one too), enumerators, Set, a user
# class, symbol procs, a named &block forward, next/break in the block,
# the with_index chains, which keep their own emitters, and the count of
# times drop_while asks (the dropped prefix and the first kept element).
# A block lifted into a proc (the each of a boxed receiver whose class
# list carries a Ruby each) keeps its break: it throws to the call site.
a = [1, 2, 3, 4, 1, 2]
p a.take_while { |x| x < 3 }
p a.drop_while { |x| x < 3 }
p a.take_while { |x| false }
p a.drop_while { |x| true }
p [].take_while { |x| true }
p [].drop_while { |x| true }
w = %w[a bb ccc d]
p w.take_while { |s| s.size < 3 }
p w.drop_while { |s| s.size < 3 }
f = [1.5, 2.5, 0.5]
p f.take_while { |x| x > 1 }
p f.drop_while { |x| x > 1 }
h = { a: 1, b: 2, c: 0 }
p h.take_while { |k, v| v > 0 }
p h.drop_while { |k, v| v > 0 }
p (1..10).take_while { |i| i * i < 30 }
p (1..10).drop_while { |i| i < 8 }
p a.each_slice(2).take_while { |x, y| x < y }
p a.take_while.each { |x| x < 4 }
e = a.take_while
p e.class
def poly(v) = v
p poly(a).take_while { |x| x < 3 }
p poly(w).drop_while { |s| s != "ccc" }
p poly(h).drop_while { |k, v| v > 0 }
class Pt
  attr_reader :x
  def initialize(x); @x = x; end
end
pts = [Pt.new(1), Pt.new(5), Pt.new(2)]
p pts.take_while { |pt| pt.x < 3 }.map(&:x)
p pts.drop_while { |pt| pt.x < 3 }.map(&:x)
require "set"
p Set[1, 2, 3].take_while { |x| x < 3 }
p a.take_while(&:odd?)
p a.drop_while(&:odd?)
def tw(&b) = [1, 2, 3].take_while(&b)
p tw { |x| x < 2 }
p tw { |x| x.to_s < "3" }
r = a.take_while { |x| x < 4 }
p r.sum
p a.take_while { |x| next false if x == 3; true }
p a.take_while { |x| break :stop if x == 4; x < 10 }
p a.take_while.with_index { |x, i| i < 2 }
p a.drop_while.with_index { |x, i| i < 4 }
count = 0
p a.drop_while { |x| count += 1; x < 3 }
p count
p (1..).take_while { |i| i < 5 }
fib = Enumerator.new { |y| f0, f1 = 0, 1; loop { y << f0; f0, f1 = f1, f0 + f1 } }
p fib.take_while { |x| x < 30 }
e = [3, 1, 2].each
p e.take_while { |x| x > 1 }
p loop.take_while { |x| false } rescue p $!.class
p (1..Float::INFINITY).take_while { |i| i * i < 20 }
def tw(a)
  out = []
  a.each do |x|
    break unless yield x
    out << x
  end
  out
end
p tw(Set[1, 2, 3]) { |x| x < 3 }
p tw(poly([1, 2, 3])) { |x| x < 3 }
