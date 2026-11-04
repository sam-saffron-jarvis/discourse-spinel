# Iterating an Enumerator held in a boxed slot: `[h.each_pair, 0][0].map`
# asked the Enumerator for a length and an element it has no read of its
# own, walked zero elements and answered []. A boxed Struct's each_pair
# (#5086) reached the same path.

h = { a: 1, b: 2 }
e = [h.each_pair, 0][0]
p e.map { |k, v| k }
p e.map { |pair| pair }

S = Struct.new(:a, :b)
s = [S.new(1, 2), 0][0]
p s.each_pair.map { |k, v| k }
p s.each.map { |x| x * 10 }

a = [[1, 2, 3].each, 0][0]
p a.map { |x| x + 1 }
