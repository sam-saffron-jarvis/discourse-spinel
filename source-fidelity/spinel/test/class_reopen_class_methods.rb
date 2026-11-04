# A method added to Class is a class method of every class: `Klass.m`, and a
# bare `m` in any class body, where self is that class. Adding one by
# reopening Class compiled a user class named Class that clashed with the
# runtime's own type, and `Class.class_eval { include M }` compiled to a
# NoMethodError at run time. This is how a gem hands every class a DSL macro
# (state_machines' `Class.class_eval { include StateMachines::MacroMethods }`).
module Macros
  def macro(tag, n = 1, &blk)
    @tags ||= []
    @tags << tag
    blk.call(self, tag, n) if blk
    self
  end

  def tags = @tags
end

module Labels
  def label = "<#{name}>"
end

class Class
  include Macros

  def kind_label(suffix)
    "#{name}-#{suffix}"
  end
end

Class.class_eval { include Labels }

Class.class_eval do
  def twice(x) = [x, x]
end

class Vehicle
  macro(:wheels, 4) { |k, t, n| puts "#{k.name} #{t} #{n}" }
  macro :engine
  p kind_label("v")
  p label
  p twice(:v)
end

class Car < Vehicle
  macro(:doors, 2) { |k, t, n| puts "#{k.name} #{t} #{n}" }
  p kind_label("c")
  p label
end

class Boat
  macro(:hull) { |k, t, n| puts "#{k.name} #{t} #{n}" }
end

# A class's own singleton method still comes first.
class Plane
  def self.label = "plane"
end

p Vehicle.tags
p Car.tags
p Boat.tags
p Boat.macro(:sail).equal?(Boat)
p Boat.tags
p Car.kind_label("x")
p Boat.label
p Plane.label
p Car.twice(:c)
