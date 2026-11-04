# Array set operations match elements by hash/eql?, not ==: 2 and 2.0 are
# different elements, so neither removes, dedupes against nor intersects
# with the other -- in a mixed array, between an Integer and a Float array,
# and inside nested arrays. include? stays ==.

a = [1, 2, "y"]
p a - [2.0]
p a | [2.0]
p a & [2.0]
p a.difference([2.0]), a.union([2.0]), a.intersection([2.0]), a.intersect?([2.0])

b = [1, 2, 3]
f = [2.0, 3.0]
p b - f, b | f, b & f, b.intersect?(f)
p f - b, f | b, f & b

x = [[1, 2], "q"]
p x - [[1, 2.0]], x & [[1, 2]], x | [[1, 2.0]]

p a.include?(2.0), [1, 2.0, 2].uniq
