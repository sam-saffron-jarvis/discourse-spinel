# #hash on a BOXED receiver answers the Integer sp_rbval_hash_key answers:
# a user #hash in the program is reached inside it and folded to the key.
# With a user #hash present the static type came from the user-method
# union instead -- poly under --int-overflow=promote -- so `h ^= x.hash`
# handed an sp_int to sp_poly_bitop's boxed parameter and the C did not
# build; `require "set"` was the first casualty (Set#hash is that loop).
class Pt
  attr_reader :x, :y
  def initialize(x, y) = (@x, @y = x, y)
  def hash = [x, y].hash
  def eql?(o) = o.is_a?(Pt) && x == o.x && y == o.y
end

def combine(items)
  h = items.size
  items.each { |x| h ^= x.hash }
  h
end

a = [1, "a", :s, 2.5, nil, [1, 2], Pt.new(1, 2)]
p combine(a).class
p combine(a) == combine(a.dup)
p combine([Pt.new(1, 2)]) == combine([Pt.new(1, 2)])
p combine([Pt.new(1, 2)]) == combine([Pt.new(2, 1)])
box = a
p box[6].hash == Pt.new(1, 2).hash
p box[0].hash == 1.hash
p box[1].hash == "a".hash
p({ Pt.new(1, 2) => :v }[Pt.new(1, 2)])

require "set"
s = Set.new([1, 2, 2, 3])
p s.size
p s.hash == Set.new([3, 2, 1]).hash
p s.include?(2)
p [s, s.dup].map(&:hash).uniq.size
