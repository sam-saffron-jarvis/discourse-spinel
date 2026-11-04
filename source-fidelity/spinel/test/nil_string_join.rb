# nil meeting a String at a ternary, an `if` without else, a `return nil if`,
# a `case` with no matching arm, a local write or a `next nil` is the nullable
# String (`const char *` NULL), the slot `&.`, an ivar and an --rbs `String?`
# already hand out -- not untyped. The join used to widen to the boxed slow
# path, and `return nil if v.nil?` at the head of a method was the largest
# single source of untyped slots in a real tree. Integer, Float and bool
# keep their join for now (#4567, rubys).
class R
  def initialize; @s = nil; @i = nil; end
  def s = @s
  def s=(x); @s = x; end
  def i = @i
  def i=(x); @i = x; end
end
def a(v) = v&.upcase
def b(v) = v.nil? ? nil : v.upcase
def c(v)
  return nil if v.nil?
  v.upcase
end
def d(n)
  t = nil
  t = "y" if n > 5
  t
end
def e(n)
  case n
  when 9 then "nine"
  end
end
def f(n)
  if n > 5 then "big" end
end
def g(n)
  s = "s"
  s = nil if n < 5
  s
end
r = R.new
r.s = "x" if ARGV.length > 5
r.i = 3 if ARGV.length > 5
n = ARGV.length
puts a(r.s).to_s, b(r.s).to_s, c(r.s).to_s, d(n).to_s, e(n).to_s, f(n).to_s
p b(r.s), c(r.s), d(n), e(n), f(n), g(n)
p [b(r.s), c(r.s)].compact
p g(n).nil?, g(n) ? 1 : 2, (g(n) || "dflt")
p ["a", "b"].map { |x| next nil if x == "a"; x }
begin
  p c(r.s).length
rescue NoMethodError => ex
  puts ex.message
end
# every written arm raising is the implicit nil, held as the String's nil
def h(g, f)
  y = if g then "s" elsif f then raise "x" elsif !f then raise "z" end
  y
end
p h(true, false)
begin
  h(false, false)
rescue => ex
  p ex.message
end
p "#{c(r.s)}|#{d(n)}"
p c(r.s) == nil, c(r.s) == "x"
x = c(r.s)
x = "z" if x.nil?
p x
# a value-position write into a shared-string ivar answers the String face
class Box
  def initialize; @body = nil; end
  def w(v) = (@body = v.nil? ? nil : v.to_s)
  def stamp; b = @body; b << "!" unless b.nil?; b; end
  def body = @body
end
bx = Box.new
p bx.w(String.new("hi"))
bx.stamp
puts bx.body
p bx.w(nil)
p bx.body
