# An argless cycle never stops: #next and #peek start over, #size is
# Infinity, and take / first / lazy read as far as they ask
e = [1, 2].cycle
p e.next, e.next, e.next, e.next
p e.size
f = [1, 2].cycle(2)
p f.size
p f.to_a
p [1, 2].cycle.lazy.map { |x| x + 1 }.first(3)
p [1, 2, 3].cycle.first(7)
p [].cycle.size
p [1, 2].cycle.take(5)
g = [1, 2].cycle
p g.take(3)
p (1..2).cycle.first(3)
g = [1, 2, 3].cycle
p g.first(5)
p g.first
p g.peek, g.next, g.next, g.next, g.next, g.peek
g.rewind
p g.next
p g.inspect
out = []
g.each_with_index { |x, i| break if i > 4; out << x }
p g.lazy.select(&:odd?).first(3)
p g.find { |x| x > 2 }
p [].cycle.first(3)
