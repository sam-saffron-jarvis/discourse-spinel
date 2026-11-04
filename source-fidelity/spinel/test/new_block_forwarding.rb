# A block reaching `Klass.new` when initialize stores it as `&handler`.
# The forwarding method is yield-inlined into its caller, so a forwarded
# `&blk` named a local no inline site declared, and an anonymous `&` was
# threaded as NULL. The analyzer also resolved `Klass.new` to a class
# method `new` that doesn't exist, so a forward (or a literal block) into
# the storing initialize never counted as an escape and its captures got
# no cells.

class Register
  def initialize(&handler)
    @handler = handler
  end

  def poke(value) = @handler.call(value)
end

# 1. anonymous `&` forwarded into the constructor
def install(&) = Register.new(&)
install { |v| puts "anon #{v}" }.poke(1)

# 2. anonymous `&` in an instance method
class AnonBus
  def install(&)
    @register = Register.new(&)
  end

  def poke(value) = @register.poke(value)
end
bus = AnonBus.new
bus.install { |v| puts "anon-ivar #{v}" }
bus.poke(2)

# 3. named `&block`, with a positional argument, capturing a caller local
class Tagged
  def initialize(tag, &handler)
    @tag = tag
    @handler = handler
  end

  def poke(value) = @handler.call(@tag, value)
end

class Box
  attr_accessor :code
end

class NamedBus
  def install(&blk)
    @reg = Tagged.new(:named, &blk)
  end

  def poke(value) = @reg.poke(value)
end
box = Box.new
nb = NamedBus.new
nb.install { |tag, value| box.code = "#{tag} #{value}" }
nb.poke(3)
puts box.code

# 4. a literal block to `new` that reads the outer block param
class WrapBus
  def install(&handler)
    @register = Tagged.new(:wrap) { |tag, value| handler.call("#{tag} #{value * 10}") }
  end

  def poke(value) = @register.poke(value)
end
wb = WrapBus.new
wb.install { |s| puts s }
wb.poke(4)

# 5. two install sites, the second's block wins; captures stay shared
total = 0
nb2 = NamedBus.new
nb2.install { |_, v| total += v }
nb2.install { |_, v| total += v * 100 }
nb2.poke(5)
p total
