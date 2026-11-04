# A boxed Range's each / map raised NoMethodError once a program class
# defined the same iterator: the mixed dispatch had no Range arm (#4840).

class Bag
  def each = yield 9
  def map = [yield(1)]
end
Bag.new.each { |v| p v }
p Bag.new.map { |v| v + 1 }
r = [0..2, "x"][0]
r.each { |v| p v }
p r.map { |v| v * 10 }
p r.select { |v| v > 0 }
Pt = Struct.new(:x)
Pt.new(1)
q = [(5...7), "x"][0]
q.each { |v| p v }
p [[5, 6], "x"][0].map { |v| v + 1 }
