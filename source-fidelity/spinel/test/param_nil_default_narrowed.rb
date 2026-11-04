# A trailing parameter defaulting to nil, narrowed to an unboxed number by
# another call site: the defaulted call passed SP_INT_NIL, and boxing it into
# a member wrapped the sentinel as a real Integer -- truthy, non-nil?, class
# Integer, while inspect still said nil. The nil literal in a parameter
# DEFAULT now marks the slot nullable, the same mark a nil-carrying argument
# always set, so only the boxing changes (#4212).
Place = Data.define(:path, :line) do
  def self.of(path, line = nil)
    new(path: path, line: line)
  end
end

one = Place.of("a.rb")
two = Place.of("b.rb", 4)
puts one.line.nil?
puts one.line.class
puts one.line.inspect
puts two.line.inspect
puts (one.line == nil)
puts two.line.class

# The Float narrowing, same shape.
FPlace = Data.define(:path, :at) do
  def self.of(path, at = nil)
    new(path: path, at: at)
  end
end

fo = FPlace.of("a.rb")
ft = FPlace.of("b.rb", 4.5)
puts fo.at.nil?
puts fo.at.class
puts ft.at.inspect

# Struct spelling.
SPlace = Struct.new(:path, :line) do
  def self.of(path, line = nil)
    new(path, line)
  end
end

so = SPlace.of("a.rb")
st = SPlace.of("b.rb", 7)
puts so.line.nil?
puts so.line.class
puts st.line.inspect

# A leading number parameter beside the defaulted one.
QPlace = Data.define(:size, :line) do
  def self.of(size, line = nil)
    new(size: size, line: line)
  end
end

qo = QPlace.of(9)
qt = QPlace.of(9, 4)
puts qo.line.nil?
puts qt.line.inspect

# The defaulted parameter used in arithmetic on the non-defaulted path keeps
# answering as a plain number.
def bump(n = nil)
  return -1 if n.nil?
  n + 1
end

p bump
p bump(41)
