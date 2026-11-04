# #4846 (hash): a store keeping one class in a hash reads it typed; infer-test
# checks each_value binds an sp_Item * and the call on it is direct.
class Item
  def initialize(n) = @n = n
  def describe = "i#{@n}"
end
class Tag
  def describe = "t"
end
class Store
  def initialize = @items = {}
  def put(k, v) = @items[k] = v
  def render
    out = []
    @items.each_value { |it| out << it.describe }
    out
  end
end
s = Store.new
s.put("a", Item.new(1))
p s.render
p Tag.new.describe
