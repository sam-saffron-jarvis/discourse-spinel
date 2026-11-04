# Enumerable#cycle with a block, written in Ruby (builtins/enumerable.rb)
out = []
[1, 2].cycle(2) { |x| out << x }
p out
out = []
p([1, 2, 3].cycle { |x| out << x; break :done if out.size == 7 })
p out
p [].cycle { |x| p x }
p [1, 2, 3].cycle(-1) { }
p [1, 2].cycle(0) { |x| p x }
out = []
(1..3).cycle(2) { |x| out << x }
p out
out = []
{ a: 1 }.cycle(2) { |k, v| out << [k, v] }
p out
class Bag
  include Enumerable
  def each; yield 1; yield 2; end
end
out = []
Bag.new.cycle(3) { |x| out << x }
p out
begin; [1].cycle("a") { }; rescue TypeError => e; p e.message; end
out = []
[1, 2].cycle(2.9) { |x| out << x }
p out
p [1, 2, 3].cycle.first(7)
def poly(x) = x
out = []
poly([4, 5]).cycle(2) { |x| out << x }
p out
n = 0
[1, 2].cycle do |x|
  n += 1
  next if x == 1
  break if n > 5
end
p n
p [1, 2].cycle(2).to_a
p [1, 2].cycle(2).map { |x| x * 10 }
p (1..2).cycle.take(5)
p [1, 2, 3].cycle(-1) { }
p [1,2].cycle(0) { |x| p x }
out=[]
[1,2].cycle(2) { |x| out << x }
p out
