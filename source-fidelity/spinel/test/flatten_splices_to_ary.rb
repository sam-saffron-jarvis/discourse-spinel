# Array#flatten splices in an element that answers #to_ary, as CRuby does for
# any element that converts (the implicit conversion Array() uses). It stayed
# in the array (#5057): a Relation-like object in `[story, merged].flatten`.
class Item
  def initialize(n) = @n = n
  def n = @n
end
class Batch
  def initialize(items) = @items = items
  def to_ary = @items
end
class NotArray
  def to_ary = nil
  def n = 0
end

list = [Item.new(1), Batch.new([Item.new(2), Item.new(3)])].flatten
p list.length
p list.map { |i| i.n }

nested = [Item.new(1), [Batch.new([Item.new(2), [Item.new(3)]]), Item.new(4)]].flatten
p nested.map { |i| i.n }

one = [Item.new(1), Batch.new([Item.new(2), [Item.new(3)]])].flatten(1)
p one.map { |x| x.is_a?(Array) ? x.map { |i| i.n } : x.n }

stay = [Item.new(1), NotArray.new].flatten
p stay.map { |i| i.n }

batches = [Batch.new([Item.new(5)]), Batch.new([Item.new(6), Item.new(7)])].flatten
p batches.map { |i| i.n }
