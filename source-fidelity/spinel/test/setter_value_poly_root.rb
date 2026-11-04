# A hand-written setter called in value position with a poly right-hand
# side (a String? here) — #4520. The value-position arm binds a non-simple argument
# to a temporary the call reads; that temporary is an sp_RbVal, and its
# root has to be the RbVal kind. needs_root() answers yes for TY_POLY too,
# so testing it first gave the temporary a plain root, and the next mark
# read the RbVal's tag word as an object pointer.
class Box
  def initialize
    @v = nil
  end

  def v=(x)
    @v = x
  end

  def v
    @v
  end
end

def pick(i)
  i.odd? ? "s#{i}" : nil
end

b = Box.new
n = 0
200_000.times do |i|
  r = (b.v = pick(i))
  n += 1 if r
  s = "x" * 64
  n += 0 if s.empty?
end
puts n
p b.v
