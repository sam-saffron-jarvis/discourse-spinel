# A local, parameter or ivar typed as a user class may hold nil, the NULL
# pointer. is_a?, kind_of?, instance_of? and #class on it answered for the
# class alone: `v.is_a?(Shape)` was true and `v.class` was Shape. nil is an
# instance of NilClass, Object, Kernel and BasicObject and of nothing else.
class Shape; end
class Sub < Shape; end
class MyErr < StandardError; end
def shape(f) = f ? Shape.new : nil
$calls = 0
def counted(f)
  $calls += 1
  f ? Sub.new : nil
end

v = shape(false)
w = shape(true)
p [v.is_a?(Shape), v.kind_of?(Object), v.is_a?(Kernel), v.is_a?(BasicObject), v.is_a?(NilClass)]
p [v.instance_of?(Shape), v.instance_of?(NilClass), v.class]
p [w.is_a?(Shape), w.kind_of?(Object), w.is_a?(NilClass), w.instance_of?(Shape), w.class]

c = NilClass
p [v.is_a?(c), v.instance_of?(c), w.is_a?(c)]

# the receiver is evaluated once
p [counted(false).is_a?(Shape), counted(true).is_a?(Shape), counted(true).instance_of?(Sub), $calls]

class Holder
  def initialize(f) = @s = f ? Shape.new : nil
  def check = [@s.is_a?(Shape), @s.class]
end
p Holder.new(false).check, Holder.new(true).check

def err(f) = f ? MyErr.new("x") : nil
e = err(false)
p [e.is_a?(StandardError), e.is_a?(MyErr), e.class]
e2 = err(true)
p [e2.is_a?(StandardError), e2.is_a?(MyErr), e2.class]
