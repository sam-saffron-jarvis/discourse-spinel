# A value-type object reached boxed (the class picked at run time) renders
# through its own #to_s and #inspect. The runtime's to_s/inspect dispatchers
# skipped value-type classes, so `puts obj`, "#{obj}" and `p obj` fell to
# the #<A:0x...> / #<Object> default past the user's methods.
class A
  def initialize(x) = @x = x
  def to_s = "A(#{@x})"
end
class B
  def initialize(x) = @x = x
  def to_s = "B(#{@x})"
  def inspect = "#<B #{@x}>"
end
class C
  def initialize(x) = @x = x
end
A.new(1)
B.new(2)
C.new(3)
def pick(i) = i == 0 ? A : (i == 1 ? B : C)
def build(i) = pick(i).new(5)
puts build(0)
puts build(1)
puts "<#{build(1)}>"
s = build(0).to_s + "|" + build(1).to_s
puts s
p build(1)
puts build(2).to_s.start_with?("#<C")
