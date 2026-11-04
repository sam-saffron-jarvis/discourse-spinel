# #4846: the Store below keeps @list as an sp_PtrArray of Item, and `x.name`
# in the map is a direct field read; infer-test greps the emitted C.
class Item
  attr_reader :name
  def initialize(n) = @name = n
end
class Tag
  attr_reader :name
  def initialize(n) = @name = n
end
class Store
  def initialize = @list = [Item.new("a")]
  def put(i) = @list << i
  def names = @list.map { |x| x.name }
end
s = Store.new
s.put(Item.new("b"))
p s.names
p Tag.new("t").name
