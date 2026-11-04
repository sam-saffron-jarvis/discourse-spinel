# A top-level Class.class_eval adds methods to Class only with a literal
# block that takes no parameters; with one, it is refused for its shape,
# not for where it is written.
Class.class_eval do |k|
  def hi = 1
end
class Foo; end
p Foo.hi
