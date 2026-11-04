# is_a? / kind_of? as a condition (if, unless, ternary) on a slot typed as a
# user class that holds nil: the condition was folded true from the static
# type. nil is none of these; a live object still answers yes.
module Named; end
class Shape; include Named; end
def shape(f) = f ? Shape.new : nil
v = shape(false)
if v.is_a?(Shape) then puts "if-yes" else puts "if-no" end
puts(v.is_a?(Named) ? "tern-yes" : "tern-no")
puts "unless" unless v.kind_of?(Shape)
w = shape(true)
if w.is_a?(Shape) then puts "w-yes" else puts "w-no" end
