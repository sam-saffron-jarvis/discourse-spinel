# A block reaching a stored-block initialize through every spelling of
# `new`: a static K.new(&h) in a method that gets inlined (it read the
# callee's lv_h, undeclared at the site), a Class value with and without
# arguments (refused, or NULL), a boxed receiver, an anonymous `&`, and a
# class method's bare and self-receiver new with arguments.
class Reg0
  def initialize(&h) = @h = h
  def poke(v) = @h.call(v)
end
def mk(&h) = Reg0.new(&h)
p mk { |v| v * 2 }.poke(21)
pr = proc { |v| v + 1 }
p Reg0.new(&pr).poke(1)
class Reg
  def initialize(n = 0, &h) = (@n = n; @h = h)
  def poke(v) = @h.call(v + @n)
end
class Other
  def initialize(n = 0, &h) = (@n = n; @h = h)
  def poke(v) = @h.call(v - @n)
end
def pick(i) = i == 0 ? Reg : Other
def mk0(i, &h) = pick(i).new(&h)
def mk1(i, &h) = pick(i).new(10, &h)
REG = {0 => Reg, 1 => Other}
def mk2(i, &h) = REG.fetch(i).new(10, &h)
def mk3(i, &) = pick(i).new(1, &)
p mk0(0) { |v| v * 2 }.poke(21)
p mk0(1) { |v| v * 3 }.poke(1)
p mk1(0) { |v| v * 2 }.poke(1)
p mk1(1) { |v| v * 2 }.poke(20)
p mk2(1) { |v| v + 100 }.poke(20)
p mk3(0) { |v| v }.poke(1)
class K
  def self.make(n, &h) = new(n, &h)
  def self.make2(&) = self.new(3, &)
  def initialize(n, &h) = (@n = n; @h = h)
  def poke = @h.call(@n)
end
p K.make(4) { |n| n * 10 }.poke
p K.make2 { |n| n * 10 }.poke
