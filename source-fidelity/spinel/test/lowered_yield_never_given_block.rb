# A yielding method whose receiver parameter is boxed and whose class list
# carries a Ruby each takes its proc form; when no call site gives it a
# block, its `if block_given?` arm is dead at every site but still compiled,
# and the yield there had no type, which the emitter refused as a condition.
# A lowered method's yield is a call on its proc: poly. The blockless each
# on the boxed Array then answers an Enumerator (the dispatch had only the
# user class's arm, and left an Array on NoMethodError).
def m(a)
  if block_given?
    out = []
    a.each do |x|
      break unless yield x
      out << x
    end
    out
  else
    a.each
  end
end
require "set"
a = [1, 2, 3]
e = m(a)
p e.class
p e.to_a
a = Set[4, 5]
p m(a).to_a
