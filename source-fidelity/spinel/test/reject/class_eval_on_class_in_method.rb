# A method added to Class inside a method body only exists once the method
# runs, so it is refused where it is written; it compiled to a NoMethodError
# for `class_eval` at run time.
module Macros
  def macro = :ok
end

def install
  Class.class_eval { include Macros }
end

install
class Vehicle
  p macro
end
