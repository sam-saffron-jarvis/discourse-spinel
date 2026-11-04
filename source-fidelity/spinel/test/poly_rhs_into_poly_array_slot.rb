# A poly-array slot assigned from a poly RHS. The hash slots have converting
# arms in the same chain and the array one did not, so the sp_RbVal went into
# an sp_PolyArray * local and the C did not compile (#4303).
#
# The RHS is poly because the receiver is: an ivar the class never assigns
# reads as nil-typed poly, so its calls dispatch at run time and answer a
# boxed value.

class Tree
  attr_reader :label, :children
  def initialize(label, children = [])
    @label = label
    @children = children
  end
end

class Holder
  def initialize(t)
    @tree = t
  end

  # @focus is never assigned anywhere, so reads of it are poly
  def kids_of_unassigned
    kids = @focus.children
    kids.size
  end

  def kids_of_assigned
    kids = @tree.children
    kids.size
  end
end

h = Holder.new(Tree.new("a", [Tree.new("b"), Tree.new("c")]))
p h.kids_of_assigned

begin
  h.kids_of_unassigned
rescue NoMethodError => e
  p e.class.to_s
end

# the hash counterpart, which already converted, still does
class HHolder
  def initialize(x)
    @h = x
  end

  def pairs
    m = @missing.to_h
    m.size
  end

  def own
    m = @h
    m.size
  end
end

p HHolder.new({ a: 1 }).own
