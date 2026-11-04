# A throw or catch whose tag is a boxed value, an element of an Array of
# Symbols here (#4523): the tag's kind (by name for a Symbol or String, by
# identity for an object, by value for an Integer) is the value's, decided
# when it is thrown or caught. Reading the payload as an object pointer made
# `throw TAGS[1]` a tag nothing matched, raised without its name.
TAGS = [ :other, :done ]
tags = [ :other, :done ]
r1 = catch(:done) do
  throw TAGS[1]
  :fell_through
end
p r1
r2 = catch(:done) do
  throw tags[1]
  :fell_through
end
p r2
p TAGS[1] == :done
p TAGS[1].equal?(:done)
# a boxed catch tag, a boxed value, a String through the same slot, an Integer
mixed = [:t1, "s2", 7]
r3 = catch(mixed[0]) { throw :t1, 42 }
p r3
r4 = catch(mixed[1]) { throw mixed[1], :str }
p r4
r5 = catch(mixed[2]) { throw mixed[2], :int }
p r5
r6 = catch(:x) { throw mixed[0] rescue p $!.message; :rescued }
p r6
begin
  throw tags[0]
rescue UncaughtThrowError => e
  p e.message
  p e.tag
end
