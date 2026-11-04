# A leading nil is an element, not an empty collection.
p [nil, 1].min_by { |x| x.nil? ? 2 : x }
p [nil, 1].max_by { |x| x.nil? ? 0 : x }
p [nil, 1].minmax_by { |x| x.nil? ? 0 : x }

calls = 0
p [nil].min_by { |x| calls += 1; 0 }
p calls

calls = 0
p [nil].max_by { |x| calls += 1; 0 }
p calls
calls = 0
p [nil].minmax_by { |x| calls += 1; 0 }
p calls

# Empty collections never evaluate the block.
calls = 0
p [].min_by { |x| calls += 1; 0 }
p [].max_by { |x| calls += 1; 0 }
p [].minmax_by { |x| calls += 1; 0 }
p calls

# Nil may also win, including ties; false is a real element too.
p [nil, 1].min_by { |x| x.nil? ? 0 : x }
p [nil, 1].max_by { |x| x.nil? ? 2 : x }
p [nil, 1].minmax_by { |x| 0 }
p [false, true].min_by { |x| x ? 1 : 0 }
p [false, true].max_by { |x| x ? 1 : 0 }
p [false, true].minmax_by { |x| x ? 1 : 0 }

# Each element's key is evaluated exactly once, in order.
visited = []
p [nil, 2, 1].min_by { |x| visited << x; x.nil? ? 3 : x }
p visited
visited = []
p [nil, 2, 1].max_by { |x| visited << x; x.nil? ? 0 : x }
p visited
visited = []
p [nil, 2, 1].minmax_by { |x| visited << x; x.nil? ? 0 : x }
p visited

# The same distinction applies to user-defined Enumerables.
class NilFirstValues
  include Enumerable
  def initialize
    @values = [nil, 1]
  end
  def each
    @values.each { |x| yield x }
  end
end
p NilFirstValues.new.min_by { |x| x.nil? ? 2 : x }
p NilFirstValues.new.max_by { |x| x.nil? ? 0 : x }
p NilFirstValues.new.minmax_by { |x| x.nil? ? 0 : x }
