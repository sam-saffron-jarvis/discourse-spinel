# `klass::CONST` where the receiver is a class VALUE rather than a written
# path. Which constant it names is a run-time question, and the compiler
# answered it with the leaf-named one, so two different receivers read the
# same constant -- the top-level CODE for both Probe::Block and Probe::Region
# (#4257). The constants are already stored per owner; the read now switches
# on the class the value carries.
module Probe
  class Block
    CODE = "block"
    SIZE = 1
  end

  class Region
    CODE = "region"
    SIZE = 2
  end

  class Bare
  end
end

CODE = "top"

def read(klass)
  klass::CODE
end

def num(klass)
  klass::SIZE
end

p read(Probe::Block)
p read(Probe::Region)
p num(Probe::Block)
p num(Probe::Region)

# the written path and the bare constant keep their own answers
p Probe::Block::CODE
p Probe::Region::CODE
p CODE

# a class that owns no such constant is a NameError, not somebody else's
begin
  read(Probe::Bare)
rescue NameError
  puts "NameError"
end

# through a container, where the class value arrives boxed
[Probe::Block, Probe::Region].each { |k| p read(k) }

# and bound to a local first
k = Probe::Region
p read(k)
p k::CODE
