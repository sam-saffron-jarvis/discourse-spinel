# each_slice / each_cons over the shapes CRuby answers: block and
# Enumerator forms, Hash/Range/user Enumerable receivers, sizes <= 0, redo
[1, 2, 3, 4, 5].each_slice(2) { |s| p s }
p [1, 2, 3, 4, 5].each_slice(2).to_a
p [1, 2, 3, 4, 5].each_slice(2).map(&:sum)
p [1, 2, 3, 4].each_cons(2).to_a
[1, 2, 3, 4].each_cons(3) { |a, b, c| p a + b + c }
p %w[a b c d e].each_slice(2).map { |x| x.join }
p (1..7).each_slice(3).to_a
p (1..5).each_cons(2).map { |a, b| b - a }
p({ a: 1, b: 2, c: 3 }.each_slice(2).to_a)
r = [1, 2, 3].each_slice(2) { |s| s }
p r
r = [1, 2, 3].each_cons(2) { |s| s }
p r
p [1.5, 2.5, 3.5].each_cons(2).map { |a, b| a + b }
p [].each_slice(3).to_a
begin; [1].each_slice(0) { }; rescue ArgumentError => e; p e.message; end
begin; [1].each_cons(0) { }; rescue ArgumentError => e; p e.message; end
p [1, 2, 3, 4].each_slice(2).with_index.map { |s, i| s.sum * i }
e = [1, 2, 3, 4, 5].each_slice(2)
p e.next
p e.size
p [1, 2, 3].each_cons(2).size
def poly(x) = x
poly([1, "a", 2, "b"]).each_slice(2) { |k, v| p [k, v] }
class Bag
  include Enumerable
  def each; yield 1; yield 2; yield 3; end
end
p Bag.new.each_slice(2).to_a
p Bag.new.each_cons(2).to_a
out = []
[[1, :a], [2, :b], [3, :c]].each_slice(2) { |(a, b), (c, d)| out << [a, b, c, d] }
p out
x = [1, 2, 3, 4, 5, 6].each_slice(2).select { |a, b| a + b > 5 }
p x
begin; p [1].each_slice(0).to_a; rescue ArgumentError => e; p e.message; end
begin; p [1].each_cons(-1).to_a; rescue ArgumentError => e; p e.message; end
# redo re-runs the block with the same slice, not the walk around it
tries = 0
[1, 2, 3].each_slice(2) do |s|
  tries += 1
  redo if s == [3] && tries < 4
  p [s, tries]
end
begin; [1].each_slice(0) { }; rescue ArgumentError => e; p e.message; end
begin; [1].each_cons(0) { }; rescue ArgumentError => e; p e.message; end
begin; (1..3).each_slice(-1) { }; rescue ArgumentError => e; p e.message; end
begin; {a: 1}.each_cons(0) { }; rescue ArgumentError => e; p e.message; end
