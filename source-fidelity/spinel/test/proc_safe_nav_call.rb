# `pr&.call` on a nil Proc slot answers nil without calling; since a8d7023d
# made a written `.call` on nil raise, the safe-navigation form did too (#4844).

class Cart
  attr_reader :cb
  def initialize = @on_change = nil
  def on_change(&block)
    @on_change = block
  end
  def changed! = @on_change&.call
  def with_arg = @on_change&.call(1)
  def idx = @on_change&.[](2)
  def via_reader = cb&.call
end
c = Cart.new
p c.changed!
p c.with_arg
p c.idx
p c.via_reader
c.on_change { |x = 0| puts "changed #{x}"; x.to_i + 1 }
p c.changed!
p c.with_arg
p c.idx
l = nil
l = ->(v) { v * 2 } if ARGV.size > 5
p l&.call(4)
l = ->(v) { v * 2 }
p l&.call(4)
puts "done"
