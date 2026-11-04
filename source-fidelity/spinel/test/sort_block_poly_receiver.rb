# `sort` with a comparator block had no arm for a receiver that is poly rather
# than a poly ARRAY -- which is what a parameter sees when one call site hands
# it Integers and another Strings. It raised NoMethodError naming Array, on the
# first call, having printed nothing. min / max with a block were the same
# (#4290).
def sorted(items) = items.sort { |a, b| a <=> b }
def desc(items) = items.sort { |a, b| b <=> a }
def by_len(items) = items.sort { |a, b| a.to_s.length <=> b.to_s.length }
def smallest(items) = items.min { |a, b| a <=> b }
def largest(items) = items.max { |a, b| a <=> b }
def bang(items)
  items.sort! { |a, b| a <=> b }
  items
end

p sorted([3, 1, 2])
p sorted(%w[pear fig banana])
p desc([3, 1, 2])
p desc(%w[pear fig banana])
p by_len(%w[pear fig banana])
p smallest([3, 1, 2])
p smallest(%w[pear fig banana])
p largest([3, 1, 2])
p largest(%w[pear fig banana])
p bang([3, 1, 2])
p bang(%w[pear fig banana])
p sorted([])
