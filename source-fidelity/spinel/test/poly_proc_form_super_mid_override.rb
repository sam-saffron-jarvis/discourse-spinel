# The super of a proc-form clone goes to the NEAREST ancestor that defines
# the method: a parent overriding a yielding grandparent without yielding
# is the one reached, not the grandparent's clone.
class GpBase
  def each_twice
    yield 1
    yield 2
  end
end
class GpMid < GpBase
  def each_twice(&blk)
    @kept = blk
    blk.call(:mid)
  end
end
class GpLeaf < GpMid
  def each_twice(&) = super(&)
end
class GpOther < GpBase
  def each_twice(&) = super(&)
end
[GpLeaf, GpOther].each { |k| k.new.each_twice { |x| p [k.name, x] } }
