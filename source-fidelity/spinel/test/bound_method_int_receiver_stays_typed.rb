# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# `<Integer>.method(:sym)` binds the receiver into a synthesized wrapper whose
# receiver parameter is typed by the adapter emission; the bind site stores the
# receiver raw and the thunk ABI reads it as an sp_int only while the parameter
# IS an Integer. Under --int-overflow=promote the widening turned that
# parameter into a box, so the callee read a 16-byte value out of a
# pointer-sized slot and every call ended in NoMethodError or a TypeError
# naming an empty class. Both modes must answer CRuby's values.

p 10.method(:pow).call(2, 7)
p 5.method(:abs).call

bm = 5.method(:+)
p bm.call(3)

m = 0.method(:+)
p m.call(5)

inc = ->(x) { x + 1 }
dbl = 2.method(:*)
p((inc >> dbl).call(4))

fs = [->(x) { x + 1 }]
mul = 2.method(:*)
p((mul >> fs[0]).call(4))

# a wrapper in a poly slot, called through the boxed path
ms = [3.method(:-), 4.method(:*)]
p ms[0].call(1)
p ms[1].call(5)

# the wrapper's own arithmetic on the receiver follows the typed contract
big = (2**62).method(:+)
p big.call(1)

# a receiverless Kernel wrapper's first parameter is an argument, not a
# receiver: it widens with the rest and stays callable from a boxed slot
# beside a user class that owns `call`
class Handler
  def call(x) = x * 100
end
puts [method(:String)][0].call(123).inspect
puts [5.method(:+), Handler.new][0].call(5)
