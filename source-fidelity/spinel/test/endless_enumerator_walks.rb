# Walking an endless Enumerator (an argless cycle, a generator that loops)
# with each / each_with_index / with_index: a break ends the walk, and the
# Enumerator's own #next cursor is left where it was
g = Enumerator.new { |y| loop { y << 1; y << 2; y << 3 } }
out = []
g.each { |x| out << x; break if out.size == 5 }
p out
out = []
g.each_with_index { |x, i| break if i > 4; out << x }
p out
p g.with_index.first(4)
p g.next, g.next
p g.first(4)
p g.take(4)
p g.lazy.map { |x| x * 2 }.first(3)
p g.find { |x| x > 2 }
g = [1, 2, 3].cycle
p g.first(5)
p out
out = []
g.each { |x| out << x; break if out.size == 5 }
p out
p g.lazy.select(&:odd?).first(3)
p g.find { |x| x > 2 }
g = Enumerator.new { |y| loop { y << 1; y << 2; y << 3 } }
p g.with_index.first(4)
p g.next
h = [1, 2, 3].cycle
p h.with_index.first(4)
