# An Enumerator.new generator whose body iterates a user class's each (a
# yielding one, or one that forwards &b) with a block that writes to the
# yielder. The block-capture wrap that gives an inlined iterator's block a
# fresh binding per iteration took the generator's block for an iteration
# and wrapped it in a lambda; `y << x` then read the yielder as an Integer
# (Integer#<<) and every such Enumerator answered [].
class Bag
  include Enumerable
  def initialize(*a); @a = a; end
  def each; @a.each { |v| yield v }; end
end
class Fwd
  def initialize(*a); @a = a; end
  def each(&b); @a.each(&b); end
end
e = Enumerator.new { |y| Bag.new(1, 2).each { |x| y << x } }
p e.to_a
e2 = Enumerator.new { |y| Fwd.new(3, 4).each { |x| y << x * 10 } }
p e2.to_a
p e2.next, e2.next
def pairs(recv) = Enumerator.new { |y| i = 0; recv.each { |x| y << [x, i]; i += 1 } }
p pairs(Bag.new(5, 6)).to_a
p pairs([7, 8]).to_a
e3 = Enumerator.new { |y| j = 0; Fwd.new(1, 2).each { |x| y.yield [x, j]; j += 1 } }
p e3.take(1), e3.to_a
# a Fiber body's parameter is an ordinary value and a proc inside may capture it
f = Fiber.new { |v| pr = -> { Fiber.yield v * 2 }; pr.call; 9 }
p f.resume(3), f.resume
