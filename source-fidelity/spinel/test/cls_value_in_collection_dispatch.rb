# A class value reaching a poly dispatch (a collection element) must dispatch
# class-side even when the class also defines an INSTANCE method of the same
# name -- the name collision made the instance table non-empty and the switch
# came out with no arms (#4218, the ActionText filter-chain shape).
class Filter
  def self.apply(content)
    content.upcase
  end

  def apply
    "instance"
  end
end

class Shrink
  def self.apply(content)
    content.downcase
  end
end

[Filter].each { |f| puts f.apply("hi") }

# the reduce chain from the originating shape
def chain(filters, content)
  filters.reduce(content) { |acc, filter| filter.apply(acc) }
end

puts chain([Filter, Shrink], "MiXeD")

# an INSTANCE flowing through the same poly shape keeps instance dispatch
[Filter.new].each { |f| puts f.apply }

# zero-arg class method through a poly slot
class Stamp
  def self.tag
    "stamped"
  end

  def tag
    "inst-tag"
  end
end

[Stamp].each { |s| puts s.tag }
[Stamp.new].each { |s| puts s.tag }
