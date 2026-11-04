# A break out of a walk over an Array of boxed values, or over an object
# array, is the same-function goto a typed array's is, so the wrapper drops
# its sp_brk_push + setjmp scope there too. The Ruby-written any?, all?,
# none? and find break out of `__self.each`, so `chips.any?(&:busy?)` on an
# array of objects paid a setjmp per call. Values, control and the locals
# written before the break are the same either way; select! (a frame of its
# own) and a nested block keep the scope.
class Chip
  attr_reader :n
  def initialize(n) = @n = n
  def busy? = @n > 2
  def tick = @n += 1
end

class Board
  def initialize(k) = @chips = Array.new(k) { |i| Chip.new(i) }
  def tick = @chips.each(&:tick)
  def any_busy? = @chips.any?(&:busy?)
  def all_busy? = @chips.all?(&:busy?)
  def none_busy? = @chips.none?(&:busy?)
  def first_busy = @chips.find(&:busy?)&.n
  def busy_at = @chips.find_index(&:busy?)
  def count_busy = @chips.count(&:busy?)
end

[0, 1, 3, 5].each do |k|
  b = Board.new(k)
  p [b.any_busy?, b.all_busy?, b.none_busy?, b.first_busy, b.busy_at, b.count_busy]
  b.tick
  p [b.any_busy?, b.all_busy?, b.none_busy?, b.first_busy, b.busy_at, b.count_busy]
end

def walk(a)
  seen = 0
  r = a.each { |x| seen += 1; break [:at, x] if x.is_a?(Integer) && x > 2 }
  [seen, r]
end
p walk([1, "a", :b, 3, 4.5])
p walk([1, "a"])
p [1, "a", :b, 3].any? { |x| x == :b }
p [1, "a", :b, 3].all? { |x| x }
p [1, "a", nil, 3].all? { |x| x }
p [1, "a", :b, 3].find { |x| x.is_a?(Symbol) }
p [1, "a", :b, 3].take_while { |x| !x.is_a?(Symbol) }
p [1, "a", :b, 3].map { |x| break x if x == "a"; x }
p [1, "a", :b, 3].each_with_index { |x, i| break i if x == :b }

def scan(k)
  xs = []
  k.times { |i| xs << Chip.new(i) }
  hit = -1
  xs.each { |c| hit = c.n; break if c.busy? }
  last = -1
  xs.each_with_index { |c, i| last = i; break if c.n == 1 }
  [hit, last, xs.length]
end
p scan(0)
p scan(2)
p scan(6)

def keep(a)
  seen = 0
  r = a.select! { |x| seen += 1; break :stop if x == :b; true }
  [seen, r, a]
end
p keep([1, "a", :b, 3])

def nested(a)
  seen = 0
  r = a.each { |x| [1].each { |y| seen += y }; break x if x == "a" }
  [seen, r]
end
p nested([1, "a", :b])

class Other
  def busy? = true
end
p [Chip.new(1), Other.new].any?(&:busy?)
begin
  p [Chip.new(5), 7].all?(&:busy?)
rescue NoMethodError => e
  p e.class
end
