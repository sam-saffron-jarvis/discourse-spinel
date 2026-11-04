# `BLOCK::CODE` where BLOCK is a CONSTANT holding a class -- the ordinary way a
# file names a long class path once. #4257 made a `::` read answer from the
# class the value carries wherever the receiver was a parameter, a local, an
# ivar or a return value, but a constant receiver still looked like a written
# path (Probe::Block::CODE) and was resolved by its leaf, so it answered a
# top-level constant of that name, or raised NameError where two classes
# defined it (#4259).
module Probe
  class Block
    CODE = "block code"
    SIZE = 1
  end

  class Region
    CODE = "region code"
    SIZE = 2
  end
end

CODE = "top code"

BLOCK = Probe::Block
REGION = Probe::Region

# the written path and the constant-held receiver name the same constant
p Probe::Block::CODE
p BLOCK::CODE
p Probe::Region::CODE
p REGION::CODE
p BLOCK::SIZE
p REGION::SIZE

# the bare constant is still its own thing
p CODE

# a class named by a constant that IS the class keeps the written-path read
module Only
  class One
    TAG = "one"
  end
end
ONE = Only::One
p Only::One::TAG
p ONE::TAG

# through a local bound from the constant, and through a container
k = BLOCK
p k::CODE
[BLOCK, REGION].each { |kk| p kk::CODE }
