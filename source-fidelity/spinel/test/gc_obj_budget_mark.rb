# The other side of the object-budget gate from gc_obj_budget_walk.rb.
#
# The budget widens by the string live set only when the MARK is what a
# collection costs, and the two programs sit at opposite ends of that. This one
# holds a large live OBJECT graph, so every collection marks a lot and frees
# little: the gate answers "mark share 1.00" and the budget is the one `walk`
# pins by hand. Its sibling churns small arrays past a live string set, so the
# sweep is what a collection costs there and the gate declines to widen.
#
# Single-threaded on purpose, for the same reason as the sibling: with one
# worker the floor is 256 KB rather than megabytes, and the worker count is out
# of the numbers.
live = []
120000.times { |i| live << [i, i + 1, i + 2] }
strs = []
20000.times { |i| strs << ("s" * 200 + i.to_s) }
total = 0
3000.times do |k|
  a = [k, k + 1]
  total += a.length
end
puts "#{live.length} #{strs.length} #{total}"
