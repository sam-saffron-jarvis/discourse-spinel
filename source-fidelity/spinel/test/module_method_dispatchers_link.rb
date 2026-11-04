# deconstruct_keys (and to_a / to_ary / to_json) from an included module: the
# object dispatchers (sp_obj_to_h and its siblings) emitted an arm for the
# MODULE as if it had instances, naming a function only the includer defines,
# and the program did not link (#4654, the shape of #4533 at three more
# switches). Reduced from vector2d 3.0.0; the dynamic send, the module-held
# deconstruct_keys and the hash pattern over an unresolved subject are what
# it takes.
class Vector2d
  module Arithmetic
    def calculate_each(method, other)
      build(
        y.send(method, v.y)
      )
    end
  end
  module Conversions
    def deconstruct_keys(_keys)
      to_hash
    end
    def to_hash
      { x: x, y: y }
    end
  end
  module Coordinates
  end
end
class Vector2d
  include Vector2d::Arithmetic
  include Vector2d::Conversions
  attr_reader :x, :y
  def initialize(x, y)
  end
end
def t(label)
  print label, ": "
  puts(yield.inspect)
rescue StandardError => e
  puts e.class
end
a = Vector2d.new(3, 4)
t("new")        { [a.x, a.y] }
t("pattern_h")  { case a; in {x:, y:} then "hash #{x} #{y}"; end }
def t(label)
  print label, ": "
  puts(yield.inspect)
end

a = Vector2d.new(3, 4)
t("new")     { [a.x, a.y] }
t("pattern") { case a; in { x:, y: } then "hash #{x} #{y}" end }

module Listy
  def to_a = [1, 2]
  def to_ary = [3, 4]
end
class Holder
  include Listy
end
def any(i) = [Holder.new, "x"][i]
p Array(any(0))
p any(0).to_a
p any(0).to_ary
