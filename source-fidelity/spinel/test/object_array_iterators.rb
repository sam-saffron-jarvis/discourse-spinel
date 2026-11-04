# An array that holds one class and is walked by each, each_with_index,
# reverse_each, each_entry or map is a typed object array (sp_PtrArray), and a
# call on an element is a direct call rather than a switch over every class
# answering the name (#4846). Mixed shapes stay boxed and still answer.

class Item
  attr_reader :name, :n
  def initialize(name, n)
    @name = name
    @n = n
  end
end
class Tag
  attr_reader :name
  def initialize(n) = @name = n
end
class Store
  def initialize = @list = [Item.new("a", 1)]
  def put(i) = (@list << i; nil)
  def names = @list.map { |x| x.name }
  def total
    t = 0
    @list.each { |x| t += x.n }
    t
  end
  def indexed
    out = []
    @list.each_with_index { |x, i| out << "#{i}:#{x.name}" }
    out
  end
  def rev
    out = []
    @list.reverse_each { |x| out << x.name }
    out
  end
  def entries_names
    out = []
    @list.each_entry { |x| out << x.name }
    out
  end
  def sum_n = @list.reduce(0) { |a, x| a + x.n }
  def pairs = @list.zip([10, 20, 30]).map { |x, y| "#{x.name}#{y}" }
  def first_name = @list[0].name
end
s = Store.new
s.put(Item.new("b", 2))
s.put(Item.new("c", 3))
p s.names
p s.total
p s.indexed
p s.rev
p s.entries_names
p s.sum_n
p s.pairs
p s.first_name
p Tag.new("t").name
list = [Item.new("x", 5)]
list << Item.new("y", 6)
p list.map { |i| i.n * 2 }
