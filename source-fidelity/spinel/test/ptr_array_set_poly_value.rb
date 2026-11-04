# `t[i] = <poly value>` on a narrowed pointer array.
#
# A poly value carries its pointer under a tag, so the element slot takes the
# pointer, not the sp_RbVal. The push arm has unboxed it since #4293; `[]=` did
# not, so a value whose static type widened -- here a helper answering its
# argument, called once with something else -- initialized a typed element
# pointer from an sp_RbVal and the generated C did not compile at all.
#
# All three pointer-array kinds take the same arm and are covered here:
# an object array, an array of int-arrays, and an array of float-arrays.
def echo(x) = x

p echo(9)          # widen echo's return to poly; every use below is the narrowed kind

class Box
  attr_reader :v
  def initialize(v)
    @v = v
  end
end

boxes = [Box.new(1), Box.new(2)]
boxes[0] = echo(Box.new(3))
p boxes[0].v
p boxes[1].v
p boxes.length

ints = [[1, 2], [3, 4]]
ints[1] = echo([7, 8])
p ints[0]
p ints[1]
p ints.length

floats = [[1.5, 2.5], [3.5, 4.5]]
floats[0] = echo([7.5, 8.5])
p floats[0]
p floats[1]
p floats.length

# the non-poly value still takes the direct path, and both kinds still read back
ints[0] = [10, 20]
floats[1] = [10.5, 20.5]
p ints[0][1]
p floats[1][0]
