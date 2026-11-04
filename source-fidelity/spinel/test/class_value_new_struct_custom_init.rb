# `k.new(v)` on a Class value (a method returning a class) that is a Struct
# with its own initialize: the positional arm skipped such a Struct, so the
# call raised NoMethodError, while the splat form built it.
class A
  def initialize(x) = @x = x
  def to_s = "A(#{@x})"
end
S = Struct.new(:x, :y) do
  def initialize(a) = super(a, a * 2)
end
def pick(i) = i == 0 ? A : S
def build(i, *args) = pick(i).new(*args)
def one(i, v) = pick(i).new(v)
puts build(0, 5)
v = build(1, 5)
p v
w = one(1, 6)
p w
