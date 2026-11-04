# A middle class re-declares an accessor that its parent overrides with a
# `def`. The inherited reader/writer flags were copied down past the def, so
# the middle class's own attribute looked inherited: a `super` below it went
# on to the def, and a plain call read the attribute instead of the def.

# 1. writer: Leaf's super reaches Mid's attr_writer, not Parent's def
class Grand
  attr_accessor :x
end
class Parent < Grand
  def x=(v)
    @x = v * 10
  end
end
class Mid < Parent
  attr_writer :x
end
class Leaf < Mid
  def x=(v)
    super
  end
end
l = Leaf.new
l.x = 3
p l.x

# 2. reader: the same shape through attr_reader
class RGrand
  attr_reader :y
  def initialize = @y = 5
end
class RParent < RGrand
  def y = @y * 100
end
class RMid < RParent
  attr_reader :y
end
class RLeaf < RMid
  def y = super + 1
end
p RLeaf.new.y

# 3. no super: a class under the def that re-declares only the writer still
#    reads through the def
class DGrand
  attr_accessor :z
end
class DParent < DGrand
  def z=(v)
    @z = v * 10
  end
  def z = @z + 1
end
class DMid < DParent
  attr_writer :z
end
class DOther < DParent
end
m = DMid.new
m.z = 3
p m.z
o = DOther.new
o.z = 3
p o.z
