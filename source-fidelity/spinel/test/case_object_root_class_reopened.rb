# With `class BasicObject` reopened, an instance of BasicObject itself is
# still neither an Object nor a Kernel, while an instance of a user class is
# an Object.
# On ec604b80 the sixth line prints the no-match answer (shape other) and the
# other six already print what the .expected holds.
class BasicObject
  def blank? = true
end
class Shape; end

root = BasicObject.new
s = Shape.new

def root_kind(v)
  case v
  when Object then "object"
  else "other"
  end
end

puts(case root; in Object then "root object"; else "root other"; end)
puts(case root; in Kernel then "root kernel"; else "root other"; end)
puts(case root; when Kernel then "root when kernel"; else "root when other"; end)
puts root_kind(root)
puts(case root; in BasicObject then "root basic"; else "root other"; end)
puts(case s; in Object then "shape object"; else "shape other"; end)
puts root.blank?
