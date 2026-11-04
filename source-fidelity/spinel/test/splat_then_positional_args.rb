# A splat followed by more positionals binds by the count the run time
# knows: every positional is gathered in order, the count is checked, and
# each parameter takes its place in that list, as CRuby does.

def g(a, b, c) = [a, b, c]
def h(a, b = 9, c = 8) = [a, b, c]
def f(a, b) = [a, b]
def s(x, y) = x + y
one = [1]; two = [1, 2]; zero = []
p g(*two, 3)
p g(*one, 2, 3)
p g(*zero, 1, 2, 3)
p g(0, *one, 3)
p h(*one, 5)
p h(*two, 5)
p h(0, *zero, 7)
p s(*["a"], "b")
begin
  p f(*two, 3)
rescue ArgumentError => e
  puts "ArgumentError: #{e.message}"
end

class B
  def initialize(a, b) = (@a = a; @b = b)
  def to_s = "B(#{@a}, #{@b})"
end
class C
  def initialize(a, b, c) = (@a = a; @b = b; @c = c)
  def to_s = "C(#{@a}, #{@b}, #{@c})"
end
puts B.new(*one, 2)
begin
  B.new(*two, 3)
  puts "no error"
rescue ArgumentError => e
  puts "ArgumentError: #{e.message}"
end
k = [B, C][ARGV.size]
puts k.new(*zero, 1, 2)
