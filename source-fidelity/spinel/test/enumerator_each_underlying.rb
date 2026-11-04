# `enum.each { blk }` runs the method the Enumerator came from with that block,
# and answers what THAT method answers -- not the values the Enumerator yields
# (#4332), and it has to compile at all over an each_with_index one (#4331).
p([1, 2, 3].each_with_index.each { |x, i| x })
p([1, 2, 3].each_index.each { |i| i })
p([1, 2, 3].each.each { |x| x })
p(["a", "b"].each_with_index.each { |x, i| x })
p([1, 2, 3].each_slice(2).each { |x| x })
p([1, 2, 3].each_cons(2).each { |x| x })
p([1, 2, 3].each_with_object([]).each { |x, m| m << x })
p([1, 2, 3].map.each { |x| x * 2 })
p([1, 2, 3].select.each { |x| x > 1 })
p({ a: 1, b: 2 }.each.each { |k, v| k })
r = [1, 2, 3].each_with_index.each { |x, i| x }
p r

# the block still runs over the right values in the right order
acc = []
[1, 2, 3].each_with_index.each { |x, i| acc << [x, i] }
p acc

# and the sibling chains keep their own answers
p([1, 2, 3].each.reverse_each { |x| x })
p([1, 2, 3].each_with_index.reverse_each { |x, i| x })
p([1, 2].each_with_index.reduce { |a, pair| pair })
p([1, 2, 3].map.with_index { |x, i| x * i })
