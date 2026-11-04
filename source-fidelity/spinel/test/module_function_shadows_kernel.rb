# A receiverless call resolves to the enclosing chain's own method before any
# Kernel builtin -- CRuby's ancestry. A module's `module_function` sibling is
# the shape with no top-level def of the name anywhere, which is what the
# Kernel arms tested for, so `trap(...)` beside a `def trap` reached
# Kernel#trap ("unsupported signal") and a dozen more names went the same way.
module Rt
  class Trap < StandardError; end
  module_function
  def trap(message) = raise(Trap, message)
  def div(a, b)
    trap("integer divide by zero") if b == 0
    a / b
  end
end
begin
  Rt.div(1, 0)
rescue => e
  puts "#{e.class}: #{e.message}"
end
p Rt.div(6, 3)

module K
  module_function
  def format(m) = "fmt:#{m}"
  def sprintf(m) = "spf:#{m}"
  def sleep(m) = "slept:#{m}"
  def rand(m) = "rand:#{m}"
  def srand(m) = "srand:#{m}"
  def raise(m) = "raise:#{m}"
  def throw(m) = "throw:#{m}"
  def open(m) = "open:#{m}"
  def Integer(m) = "int:#{m}"
  def Float(m) = "flt:#{m}"
  def String(m) = "str:#{m}"
  def Array(m) = "arr:#{m}"
  def Hash(m) = "hsh:#{m}"
  def all
    [format("a"), sprintf("b"), sleep(1), rand(2), srand(3), raise("r"),
     throw("t"), open("o"), Integer("i"), Float("f"), String("s"),
     Array("a"), Hash("h")]
  end
end
p K.all

# ...and a name the enclosing chain does NOT own still reaches Kernel
module U
  module_function
  def go = format("%02d", 7)
end
p U.go
