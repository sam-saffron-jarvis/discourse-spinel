# `is_a?` a module on a value whose class is only known at run time answered
# false for every class that includes the module: the test listed the
# module and its subclasses, which no instance is. The typed receiver
# answered true. `Mod === v` and a `when Mod` arm share the test.

module Greet; end
class A; include Greet; end
class Sub < A; end
class B; end

a = A.new
p a.is_a?(Greet)
[A.new, Sub.new, B.new, 1, "s"].each do |x|
  p [x.is_a?(Greet), x.kind_of?(Greet), Greet === x, x.instance_of?(A)]
  case x
  when Greet then puts "greet"
  else puts "other"
  end
end
