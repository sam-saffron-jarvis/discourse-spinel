# `arr.each_index.reverse_each` was refused outright: the blockless inner call
# answers an Enumerator and reverse_each has no arm for one. `.each` on the
# same Enumerator works, and `.to_a` on it answers the right elements, so the
# chain is served by interposing to_a -- the trick the Range enumerator chains
# already use (#4302).

[1, 2, 3].each_index.reverse_each { |i| print i }
puts

p [10, 20, 30].each_index.reverse_each.to_a
p [10, 20].each_with_index.reverse_each.to_a

# the forms that already worked, kept
[1, 2, 3].each.reverse_each { |i| print i }
puts
[1, 2, 3].reverse_each { |i| print i }
puts
[1, 2, 3].each_index.each { |i| print i }
puts
p [10, 20, 30].each_index.to_a
p [10, 20, 30].each.reverse_each.to_a

# an empty receiver walks nothing
[].each_index.reverse_each { |i| print i }
puts "empty ok"
