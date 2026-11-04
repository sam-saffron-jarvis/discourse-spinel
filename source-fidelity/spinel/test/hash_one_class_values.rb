# A hash whose values are all one class, filled by `[]=`, has its value
# reads typed as that class: `[]`, `fetch`, `values`, `each_value` (#4846).

class Item
  attr_reader :name, :n
  def initialize(name, n)
    @name = name
    @n = n
  end
  def describe = "#{@name}=#{@n}"
end
class Tag
  attr_reader :name
  def describe = "tag"
  def initialize(n) = @name = n
end
class Store
  def initialize
    @items = {}
  end
  def put(item)
    @items[item.name] = item
  end
  def fetch(name)
    @items[name]
  end
  def map_counts
    @items.values.map { |it| it.n * 2 }
  end
  def render
    out = []
    @items.each_value { |it| out << it.describe }
    out.join(",")
  end
end
st = Store.new
st.put(Item.new("a", 1))
st.put(Item.new("b", 2))
x = st.fetch("a")
p x ? x.n : 0
p st.fetch("zz")
p st.map_counts
p st.render
p Tag.new("t").describe
