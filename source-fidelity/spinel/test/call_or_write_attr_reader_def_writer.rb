# `obj.attr ||= v` / `&&=` with an attr_reader and a def writer that has no
# other call site: the reader's temp took the expression's type while the
# ivar was boxed, and the C did not compile (#4827).

class Reg
  attr_reader :value
  def initialize(v) = @value = v
  def value=(v)
    @value = v & 0x7f
  end
end
r = Reg.new(1)
r.value ||= 0x180
p r.value
q = Reg.new(5)
q.value &&= 0
p q.value

class Name
  attr_reader :value
  def initialize = @value = nil
  def value=(v)
    @value = v.upcase
  end
end
n = Name.new
n.value ||= "x"
p n.value
x = (n.value ||= "y")
p x
