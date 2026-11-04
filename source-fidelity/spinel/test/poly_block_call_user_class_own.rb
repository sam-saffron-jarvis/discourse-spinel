# A block call on a value that is an Array or an instance of a class with
# its own method of the name: the class's method answers for the class,
# the builtin for the Array (#4937)
class Bag
  def initialize(v) = @v = v
  def any? = @v
  def size = 3
end

def rows(flag) = flag ? [1, 5] : Bag.new(nil)

shown = rows(true).any? { |x| x > 3 }
p shown
p Bag.new("x").any?
[true, false].each do |f|
  r = rows(f)
  v = r.is_a?(Bag) ? r.any? { |x| x > 3 } : 0
  p v
end
p rows(false).any? { |x| x > 3 }
r = rows(false)
if r.is_a?(Bag)
  p r.size
  p r.any? { |x| x > 3 }
  p r.any?
end
