# A module_function module that is both extended and included into one class.
# `extend` hands the module's instance methods to the extending class as class
# methods, but a module_function method is registered class-level on the
# module and the extend transplant skipped it: a bare call from one of the
# class's own class methods then fell to the INSTANCE copy the include had
# made, with the class object cast to an instance pointer, and the C did not
# build (#4648). The module's own copy stays callable on the module.
module Coordinates
  module_function

  def coordinate(value)
    raise ArgumentError, "bad" if value.nil?

    value
  end
end

class Foo
  extend Coordinates
  include Coordinates

  def self.parse(arg)
    coordinate(arg)
  end
  def inst(arg) = coordinate(arg)
end

p Foo.parse(3)
p Foo.new.inst(4)
p Coordinates.coordinate(5)
begin
  Foo.parse(nil)
rescue ArgumentError => e
  puts e.message
end

module Counting
  module_function

  def countdown(n)
    return 0 if n <= 0

    countdown(n - 1)
  end
end

class Bar
  extend Counting
  include Counting

  def self.parse(n) = countdown(n)
  def inst(n) = countdown(n)
end

p Bar.parse(3)
p Bar.new.inst(2)
p Counting.countdown(1)
