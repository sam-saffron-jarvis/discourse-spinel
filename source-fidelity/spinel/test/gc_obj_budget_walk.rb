# The object collection budget widens by the string live set only when the
# MARK is what a collection costs. This program is the end where it is not:
# it churns small arrays past a live string set, so the sweep is what the
# collections cost and the gate declines to widen. gc_obj_budget_mark.rb is
# the other end, where the same binary widens all the way.
#
# SPINEL_GC_OBJ_BUDGET=walk pins the widening on and `obj` pins it off, and
# the leg reads all three so that the gate has to sit between them rather than
# at one end.
# Single-threaded on purpose: the pool-wide floor (256 KB x workers) is what
# the budget has to clear before the retune is visible at all, and with one
# worker that floor is 256 KB rather than megabytes. It also takes the worker
# count out of the numbers, which is what made a threaded version of this
# check compare two different moments and flake.
held = []
20000.times { |i| held << ("held-" * 40 + i.to_s) }

total = 0
4000.times do |k|
  a = []
  40.times { |i| a << [i, i + 1] }
  total += a.length
end
puts "#{total} #{held.length}"
