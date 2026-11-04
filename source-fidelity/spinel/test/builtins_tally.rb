# Enumerable#tally, written in Ruby (builtins/enumerable.rb)
p [1, 2, 2, 3, 3, 3].tally
p %w[a b a c a].tally
p [1.5, 2.5, 1.5].tally
p [:x, :y, :x].tally
p (1..4).map { |i| i % 2 }.tally
p({ a: 1, b: 2 }.tally)
p [[1, 2], [1, 2], [3]].tally
mixed = [1, "a", 1, nil, "a", nil]
p mixed.tally
p [].tally
e = [3, 1, 3].each
p e.tally
h = { 1 => 5 }
p [1, 2, 1].tally(h)
p h
t = [1, 2, 2].tally
t[9] = 1
p t.sum { |k, v| v }
class Bag
  include Enumerable
  def each
    yield "p"; yield "q"; yield "p"
  end
end
p Bag.new.tally
def poly(x) = x
p poly([4, 4, 5]).tally
p (1..6).each_slice(2).map(&:sum).tally
