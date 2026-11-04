# `@v += x` on a poly ivar emits a per-class arm for every user class that
# defines the operator. A value-type class takes `self` BY VALUE, so the arm
# has to dereference the boxed payload and box the struct result with
# sp_box_vobj_<C>; it passed the pointer straight into the by-value parameter
# and boxed with sp_box_obj, which did not compile. The op-assign twin of
# #4091, which fixed the same mismatch at a plain poly call site.
#
# Path is a value type: one scalar ivar, no super or sub, no in-place
# mutation. @v is a genuine poly union (Path | String | Integer), so all
# three arms of the write-back are exercised here, not just enumerated.

class Path
  def initialize(base)
    @base = base
  end
  def +(part)
    Path.new(@base + part)
  end
  def to_s
    @base
  end
end
puts (Path.new("/a") + "/b").to_s

class Box
  def initialize
    @v = ""
  end
  def as_path
    @v = Path.new("/root")
  end
  def as_int
    @v = 1
  end
  def as_string
    @v = "hi"
  end
  def grow(x)
    @v += x
  end
  def read
    @v.to_s
  end
end

b = Box.new
b.as_path
b.grow("/sub")          # the value-type arm actually runs
puts b.read
b.grow("/more")
puts b.read

s = Box.new
s.as_string
s.grow("!")             # the String arm
puts s.read

i = Box.new
i.as_int
i.grow(41)              # the numeric arm
puts i.read
