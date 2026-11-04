# A typed object local can hold nil: a method that answers nil for "none",
# a local assigned on one path. nil is an Object, a Kernel, a BasicObject
# and a NilClass and nothing else, and it has no #deconstruct or
# #deconstruct_keys.
class Shape
  attr_reader :x
  def initialize(x = 5) = (@x = x)
  def deconstruct_keys(keys) = {x: @x}
  def deconstruct = [@x, @x + 1]
end
class Sub < Shape; end
Point = Struct.new(:px, :py)
class Bare < BasicObject; end
class MyErr < StandardError; end

def shape(f) = f ? Shape.new : nil
def sub(f) = f ? Sub.new : nil
def point(f) = f ? Point.new(1, 2) : nil
def bare(f) = f ? Bare.new : nil
def err(f) = f ? MyErr.new("x") : nil

v = shape(false)
puts(case v; in Shape then "shape"; else "other"; end)
puts(case v; in Sub then "sub"; else "other"; end)
puts(case v; in nil then "nil"; else "other"; end)
puts(case v; in NilClass then "nilclass"; else "other"; end)
puts(case v; in Object then "object"; else "other"; end)
puts(case v; in Shape | nil then "shape-or-nil"; else "other"; end)
puts(case v; in Shape(x:) then "keys #{x}"; else "other"; end)
puts(case v; in {x:} then "hash #{x}"; else "other"; end)
puts(case v; in [a, b] then "array #{a} #{b}"; else "other"; end)
puts(case v; when Shape then "when-shape"; else "other"; end)
puts(case v; when nil then "when-nil"; else "other"; end)
puts(case v; when NilClass then "when-nilclass"; else "other"; end)
puts(case v; when Object, Kernel then "when-root"; else "other"; end)
case v
when Shape then puts "stmt-shape"
else puts "stmt-other"
end
case v
in Shape then puts "stmt-in-shape"
in nil then puts "stmt-in-nil"
end
puts((case v; when Shape then "expr-shape"; else "other"; end))
puts((case v; when NilClass then "expr-nilclass"; else "other"; end))
r = (v in Shape); puts r
r = (v in nil); puts r
r = (v in {x:}); puts r
r = (v in [a, b]); puts r

w = shape(true)
puts(case w; in Shape(x:) then "keys #{x}"; else "other"; end)
puts(case w; in [a, b] then "array #{a} #{b}"; else "other"; end)
puts(case w; in nil then "nil"; else "other"; end)
puts(case w; in NilClass then "nilclass"; else "other"; end)
puts(case w; when Shape then "when-shape"; else "other"; end)
s = sub(false)
puts(case s; in Shape then "shape"; else "other"; end)
puts(case s; when Shape then "when-shape"; else "other"; end)
s = sub(true)
puts(case s; in Shape then "shape"; else "other"; end)

q = point(false)
puts(case q; in Point then "point"; else "other"; end)
puts(case q; in [px, py] then "array #{px} #{py}"; else "other"; end)
puts(case q; in {px:} then "hash #{px}"; else "other"; end)
puts(case q; in nil then "nil"; else "other"; end)
puts(case q; in [] then "empty"; else "other"; end)
puts(case q; in [*] then "any"; else "other"; end)
q = point(true)
puts(case q; in [px, py] then "array #{px} #{py}"; else "other"; end)
puts(case q; in {px:} then "hash #{px}"; else "other"; end)

bo = bare(false)
puts(case bo; in Object then "object"; else "other"; end)
puts(case bo; when Kernel then "when-kernel"; else "other"; end)
puts(case bo; in BasicObject then "basic"; else "other"; end)
puts(case bo; in Bare then "bare"; else "other"; end)
bo = bare(true)
puts(case bo; in Object then "object"; else "other"; end)
puts(case bo; in Bare then "bare"; else "other"; end)

e = err(false)
puts(case e; when StandardError then "when-se"; else "other"; end)
puts(case e; in Exception then "in-ex"; else "other"; end)
e = err(true)
puts(case e; when StandardError then "when-se"; else "other"; end)
