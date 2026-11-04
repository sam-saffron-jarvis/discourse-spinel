# reverse_each with a block answers its RECEIVER. Reaching the array machinery
# through an interposed to_a made it answer that array instead (#4325), and the
# [value, index] pairs it walks have to auto-splat across a two-parameter
# block the way `each` already does (#4326).
p([1, 2, 3].each.reverse_each { |x| x })
p([1, 2, 3].each_index.reverse_each { |i| i })
p([1, 2, 3].each_with_index.reverse_each { |x, i| x })
p([1, 2, 3].reverse_each { |x| x })

[1, 2].each_with_index.reverse_each { |x, i| print "#{x}#{i}" }
puts
[1, 2].each_with_index.to_a.reverse_each { |x, i| print "#{x}#{i}" }
puts
c = [1, 2].each_with_index.to_a
c.reverse_each { |x, i| print "#{x}#{i}" }
puts
[[1, 0], [2, 1]].reverse_each { |x, i| print "#{x}#{i}" }
puts

# the single-parameter form still binds the whole pair
[1, 2].each_with_index.reverse_each { |pair| print pair.inspect }
puts

# and the iteration order is still last-to-first
acc = []
[1, 2, 3].each.reverse_each { |x| acc << x }
p acc
