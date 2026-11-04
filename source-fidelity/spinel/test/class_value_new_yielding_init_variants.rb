# A class whose initialize yields (or forwards its block), constructed through
# a Class value: the constructor still runs the body.
$runs = 0

class Plain
  def initialize(x) = @x = x
  def to_s = "Plain(#{@x})"
end

class Yielder
  def initialize(x)
    $runs += 1
    @x = x
    @y = block_given? ? yield(x) : "none"
  end
  def to_s = "Yielder(#{@x},#{@y})"
end

# forwards an anonymous block
class Forwarder
  def initialize(x, &)
    @x = x
    @y = wrap(x, &)
  end
  def wrap(v) = block_given? ? yield(v) : "bare"
  def to_s = "Forwarder(#{@x},#{@y})"
end

# inherits the yielding initialize
class SubYielder < Yielder
  def to_s = "Sub" + super
end

# no parameters at all
class NoArgs
  def initialize
    @z = block_given? ? yield : 42
  end
  def to_s = "NoArgs(#{@z})"
end

# the static sites splice the body, exactly once each
puts Yielder.new(9) { |v| v * 2 }
puts Forwarder.new(3) { |v| v + 1 }
puts NoArgs.new { 5 }
p $runs

[Plain, Yielder, SubYielder].each { |k| puts({ 0 => k }.fetch(0).new(1)) }
p $runs
puts [Forwarder][0].new(4)
k = [NoArgs, Plain][0]
puts k.new
