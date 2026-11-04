# `recv.attr op= v` with a def writer, where the receiver is a method call,
# `self.x` or an index: it was refused; now the receiver is evaluated once
# into a local and the reader and writer both run (#4826).

class Reg
  attr_reader :value
  def initialize = @value = 1
  def value=(v)
    @value = v & 0x7f
  end
end
class Holder
  attr_reader :reg
  def initialize = @reg = Reg.new
  def set(bit)
    reg.value |= bit
  end
  def add(n)
    self.reg.value += n
  end
  def clear(bit)
    reg.value &= ~bit
  end
end
h = Holder.new
h.set(0x180)
p h.reg.value
h.add(4)
p h.reg.value
h.clear(4)
p h.reg.value
h.reg.value |= 6
p h.reg.value
regs = [Reg.new, Reg.new]
regs[0].value |= 6
p regs[0].value
x = (regs[1].value += 200)
p x
p regs[1].value
[1, 2].each { |i| regs[1].value += i }
p regs[1].value
