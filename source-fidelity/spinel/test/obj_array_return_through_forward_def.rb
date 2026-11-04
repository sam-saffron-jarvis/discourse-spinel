# A method answers, as its tail, a call to a method defined further down the
# file. In the round that method's return is still unknown, so the caller
# has no return slot in the object-array narrowing, and the callee's slot
# was kept alive by the tail's statement position as if its value were
# discarded: the callee narrowed to the pointer array under a caller whose
# `map` was never vetted, and the build stopped on it (#4490). The tail of a
# slotless method is a return this pass does not model.
Capture = Struct.new(:text)

def capture = decode
def decode = [Capture.new("b")]

p capture.map { |c| c.text }

def held
  v = decode
  v
end
p held.map { |c| c.text }

# the same shape with the definitions in reading order keeps its answer
def decode2 = [Capture.new("d")]
def capture2 = decode2
p capture2.map { |c| c.text }

# and a pair whose uses this pass can all vet still narrows through the tail
class Vec
  attr_reader :x
  def initialize(x) = @x = x
end
def build = make_vecs
def make_vecs = [Vec.new(1), Vec.new(2)]
vs = build
p vs[0].x + vs[1].x
p vs.size
