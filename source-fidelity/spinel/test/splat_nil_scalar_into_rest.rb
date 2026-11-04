# *nil spreads to nothing and a scalar splat to one argument, into a rest
# and through an instance method's dispatch
def r(*xs) = xs.inspect
def q(a, *r) = [a, r].inspect
def z
  puts "z ran"
  nil
end
puts r(1, *nil)
puts r(*nil, 2)
puts r(*nil, *nil)
puts r(*z)
puts q(*[1], *nil)
puts q(*[1], *nil, 3)
puts q(1, *nil, *[2, 3])
v = [4, 5]
puts q(*[1], *v)
class O
  def m(a, b = 0) = "m(#{a},#{b})"
  def r(*xs) = xs.inspect
  def g(x) = x + 1
end
o = O.new
puts o.m(*7)
puts o.m(*"s")
puts o.r(*nil)
puts o.r(1, *nil)
puts o.r(*5)
puts o.g(*5)
begin
  o.m(*nil)
rescue ArgumentError => e
  puts "AE #{e.message}"
end
