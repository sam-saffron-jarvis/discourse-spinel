# A nested numeric table (Array[Array[Integer]] / Array[Array[Float]]) or an
# Array of one class's objects is an unboxed pointer array; reaching a slot
# that holds any kind of value used to drop it (the method answered nil,
# #4486) and then to be refused. It is boxed by reference now, stamped with
# what its elements are, so through the box the array is the same object
# and every Array method answers as for a general Array. The one rule that
# stays is the typed-array one: a store of another kind raises TypeError,
# so that section's expectation is not CRuby's, which would take the value.
class Item
  attr_reader :v
  def initialize(v)
    @v = v
  end
  def inspect = "#<Item #{@v}>"
  def to_s = "Item(#{@v})"
  def <=>(o) = @v <=> o.v
  def ==(o) = o.is_a?(Item) && @v == o.v
end
class Sub < Item
end

def int_table(n)
  t = Array.new(n) { |i| Array.new(2, i) }
  t
end
def flt_table(n)
  t = Array.new(n) { |i| Array.new(2, i * 0.5) }
  t
end
def items(n)
  a = Array.new(n) { |i| Item.new(i) }
  a
end

# each kind reaches a poly slot through a method whose value is the table on
# one path and nil on the other
def maybe_int(f) = (int_table(3) if f)
def maybe_flt(f) = (flt_table(3) if f)
def maybe_items(f) = (items(3) if f)

def try
  yield
rescue TypeError, FrozenError, IndexError, ArgumentError => e
  "#{e.class}: #{e.message}"
end

slots = { "i" => maybe_int(true), "f" => maybe_flt(true), "o" => maybe_items(true), "n" => maybe_int(false) }
%w[i f o n].each do |k|
  v = slots[k]
  puts "== #{k}"
  p v
  puts v.to_s
  puts v.class
  p v.nil?
  next if v.nil?
  p v.length
  p v.size
  p v.empty?
  p v[0]
  p v[-1]
  p v[5]
  p v.first
  p v.last
  p v.first(2)
  p v.last(2)
  p v.each { |e| }.class
  v.each_with_index { |e, i| print i, ":", e.inspect, " " }
  puts
  p v.map { |e| e.inspect }
  p v.select { |e| true }.size
  p v.reject { |e| false }.size
  p v.include?(v[1])
  p v.index(v[2])
  p v.count
  p v.to_a.size
  p v.reverse
  p v.dup
  p v.dup == v
  p v == v
  p v == v.dup
  p v.min
  p v.max
  p v.sort
  p v.sort_by { |e| -1 * (e.is_a?(Array) ? e[0] : e.v) }
  p v.join(",")
  p v.flatten
  p v.zip(v).size
  p v.take(1)
  p v.drop(2)
  p v.each_slice(2).to_a
  p v.group_by { |e| e.is_a?(Array) ? e[0] > 0 : e.v > 0 }.keys
  p v[0..1]
  p v[1, 1]
  p v.values_at(0, 2)
  p v.frozen?
  p v.any? { |e| e.nil? }
  p v.all? { |e| !e.nil? }
  p v.sum { |e| e.is_a?(Array) ? e.size : 1 }
  p v.find { |e| true }.inspect
  p v.each_cons(2).count
  p v.compact.size
  p v.uniq.size
  puts "-- mutation"
  d = v.dup
  d << v[0]
  p d.size
  d.push(v[1])
  p d.size
  p d.pop
  p d.shift
  d.unshift(v[2])
  p d[0]
  d[0] = v[1]
  p d[0]
  d.insert(1, v[0])
  p d.size
  p d.delete_at(1)
  d[d.size] = v[0]
  p d.size
  d[1..1] = [v[2]]
  p d[1]
  d.concat([v[0]])
  p d.size
  p d.delete(v[0]).inspect
  p d.size
  d.clear
  p d
  p d.empty?
  puts "-- refused"
  puts try { v << "x" }
  puts try { v.push(1) }
  puts try { v.insert(0, :s) }
  puts try { v.unshift("z") }
  puts try { v.concat(["q"]) }
  p v.size
  v[0] = v[1]
  p v[0] == v[1]
  v.freeze
  puts try { v << v[0] }
  p v.frozen?
end
puts "== subclass"
o = maybe_items(true)
o << Sub.new(9)
p o.last
p o.last.class
p o.size
puts try { o << 3 }
puts "== nested"
t = maybe_int(true)
t[0][1] = 42
p t[0]
p t.map(&:sum)
p t.flatten.sum
p t.transpose
p t.flat_map { |r| r }
h = { "t" => t }
p h["t"][1]
p h
p [t, 1]
puts "#{t}"
puts "== either"
def either(f)
  if f
    [1, "a"]
  else
    flt_table(2)
  end
end
p either(true)
p either(false)
e = either(false)
e[0][0] = 9.5
p e
p [e, either(true)].map(&:size)
