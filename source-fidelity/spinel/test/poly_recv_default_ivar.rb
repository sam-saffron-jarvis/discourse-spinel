class A
  def initialize = @k = 1
  def m(x, y = @k) = [x, y]
end
class B < A
  def initialize = @extra = 7
  def m(x, y = @extra) = [x, y]
end
class Caller
  def initialize(o) = @o = o
  def go = @o.m(2)
end
p Caller.new(B.new).go
p Caller.new(A.new).go
