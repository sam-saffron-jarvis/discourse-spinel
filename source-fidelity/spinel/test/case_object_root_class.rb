# An instance of a user class tested against Object, Kernel and BasicObject
# by case/when and by the case/in pattern forms, beside a class declared
# `< BasicObject`, which is neither an Object nor a Kernel. On ec604b80 the
# first ten lines print the no-match answer; the last three already print
# what the .expected holds.
class Shape; end
class Square < Shape; end
class Bare < BasicObject; end

s = Shape.new
q = Square.new
bare = Bare.new

def kind(v)
  case v
  in Kernel then "kernel"
  else "other"
  end
end

puts(case s; in Object then "object"; else "other"; end)
puts(case q; in BasicObject then "basic"; else "other"; end)
puts kind(q)
puts(case s; in Object => o then "bound #{o.class}"; else "other"; end)
puts((q in Object))
case s
when Object then puts "when object"
else puts "when other"
end
puts(case q; when Kernel then "when kernel"; else "when other"; end)
puts(case s; when Integer, BasicObject then "when basic"; else "when other"; end)
puts(case bare; in BasicObject then "bare basic"; else "bare other"; end)
puts(case bare; when BasicObject then "bare when basic"; else "bare when other"; end)
puts(case bare; in Object then "bare object"; else "bare other"; end)
puts(case bare; when Kernel then "bare kernel"; else "bare when other"; end)
puts(case q; in Shape then "shape"; else "other"; end)
