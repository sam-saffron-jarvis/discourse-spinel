# A receiverless const_get in a class method or a module body is sent to
# the class; it had no receiver and its value was untyped (#4843).

module Carts
  class A
    def initialize(x) = @x = x
    def x = @x
  end
  class B < A; end
  def self.literal(x) = const_get(:B).new(x)
  def self.klass = const_get(:B)
  def self.str(x) = const_get("A").new(x)
  FOUND = const_get(:A)
end
p Carts.literal(5).x
p Carts.klass
p Carts.str(7).x
p Carts::FOUND
