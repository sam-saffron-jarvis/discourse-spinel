# An Array indexed by a String or a Symbol is CRuby's TypeError. A class
# whose [] indexes an Array had its parameter typed String when the only
# call reaching it was one arm of a dispatch over several classes' [] with
# a String argument -- an arm that never runs -- and the C build failed on
# the String passed as an index (#5076).
class Keyed
  def initialize
    @h = { "k" => "v" }
  end

  def [](key)
    @h[key]
  end
end

class Listed
  def initialize(items)
    @items = items
  end

  def [](i)
    @items[i]
  end

  def first
    @items.first
  end
end

set = Listed.new([Keyed.new, Listed.new([])])
p set.first["k"]

def idx(a, k) = a[k]
begin
  idx([1, 2], "k")
rescue TypeError => e
  p e.message
end
begin
  p [1, 2].at(:s)
rescue TypeError => e
  p e.message
end
p idx([1, 2], 1)
