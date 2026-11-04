# A constant assigned `Struct.new` / `Data.define` inside a namespace is a
# class VALUE where it is read, and carries the namespace in its name.
# The constant registers before the anonymous class exists, so its recorded
# type never settles; the bare `Block` read already skipped that unsettled
# entry and fell through to the class table, but the qualified `Probe::Block`
# read returned it, typed the slot sp_RbVal, and boxed an unknown kind as nil.

module Probe
  Block = Struct.new(:kind)
  Point = Data.define(:x)
  class Region; end
end

k = Probe::Block
puts k.nil?
puts k.to_s
puts k.name
puts k.new("x").kind

d = Probe::Point
puts d.nil?
puts d.to_s

# the namespace reaches the class's own name, as a declared class's does
puts Probe::Block.new("x").class.to_s
puts Probe::Region.to_s
puts Probe::Block.equal?(Probe::Block)
puts Probe::Block.equal?(Probe::Region)

# `when <class value>`: Module#=== is membership, tested at run time
one = Probe::Block.new("x")
puts(case one when k then "matched" else "fell through" end)
puts(case one when Probe::Region then "wrong" else "no match" end)
r = Probe::Region.new
puts(case r when Probe::Region then "matched" else "fell through" end)

# the class value survives being passed and collected
def take(cls) = cls.to_s
puts take(Probe::Block)
puts [Probe::Block, Probe::Region].map(&:to_s).inspect

# two same-named structs in separate namespaces stay distinct
module A
  Item = Struct.new(:kind)
end
module B
  Item = Struct.new(:size, :color)
end
puts A::Item.members.inspect
puts B::Item.members.inspect
puts A::Item.name
puts B::Item.name

# the top-level form is unchanged
Top = Struct.new(:kind)
puts Top.name
puts Top.nil?
