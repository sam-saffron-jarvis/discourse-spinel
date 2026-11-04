# A method called on a poly receiver with a block gets a proc-form clone
# ("<m>#pf"), and its super has to find the ancestor's method. An ancestor
# that yields has a clone of its own; one that takes &blk and keeps it has
# only the plain method, and the clone raised "no superclass method 'on#pf'".
class PfBase
  def on(&handler) = @handler = handler
  def tagged(tag, &handler) = @handler = proc { |v| handler.call([tag, v]) }
  def fire(value) = @handler.call(value)
  def each_twice
    yield 1
    yield 2
  end
end

class PfA < PfBase
  def on(&) = super(&)
  def tagged(tag, &) = super(tag.to_s * 2, &)
  def each_twice(&) = super(&)
end

class PfB < PfBase
  def on(&) = super(&)
  def tagged(tag, &) = super(tag, &)
  def each_twice(&) = super
end

[PfA, PfB].each do |k|
  o = k.new
  o.on { |v| p [k.name, v] }
  o.fire(1)
  o.tagged(:t) { |v| p v }
  o.fire(2)
end

# an ancestor that yields has its own clone, and the clone's super reaches it
[PfA, PfB].each { |k| k.new.each_twice { |x| p x * 10 } }
