# A method that forwards its own optional block to a Ruby-defined Enumerable
# method (`def g(&b) = a.take_while(&b)`) and is called both with and
# without one. The forward is the block `{ |__fwd| yield __fwd }`, and the
# callee's `block_given?` used to fold to true on the strength of that
# literal, so the blockless call ran the block arm and its yield raised
# LocalJumpError. It now asks about the enclosing method's block: 1 or 0
# when the enclosing method's own calls all agree, at run time when they
# differ, and the call answers the union of the two arms' types then.
def g(&b) = [1, 2, 3].take_while(&b)
p(g { |x| x < 3 })
p g.class
def only_with(&b) = [1, 2, 3].take_while(&b)
p(only_with { |x| x < 2 })
def only_without(&b) = [1, 2, 3].take_while(&b)
p only_without.class
def h(&b) = { a: 1, b: 2 }.filter_map(&b)
p(h { |k, v| k if v == 1 })
p h.class
class W
  def initialize(a) = @a = a
  def tw(&b) = @a.take_while(&b)
end
w = W.new([5, 6, 1])
p(w.tw { |x| x > 4 })
p w.tw.class
def mb(&b) = [3, 1, 2].min_by(&b)
p(mb { |x| -x })
p mb.to_a
# a user method with the same shape keeps working
def m
  if block_given?
    yield 1
  else
    :none
  end
end
def f(&b) = m(&b)
p f
p(f { |x| x * 2 })
