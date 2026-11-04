# Integer#step and Float#step on a BOXED receiver: the poly face table left
# step out because both classes own it and an unbox to sp_int would truncate
# a Float; the row now has two owners, dispatched on the box's tag at run
# time, so an Integer box takes the Integer loop, a Float box the Float loop
# (in statement and expression position alike), and anything else raises
# CRuby's NoMethodError. The blockless form (an Enumerator) is not covered.
n = [3, nil][0]
n.step(9, 3) { |i| p i }
f = [2.5, nil][0]
f.step(9, 3) { |x| p x }
m = [10, nil][0]
m.step(1, -4) { |i| p i }
r = n.step(5) { |i| }
p r
g = [1.0, nil][0]
p(g.step(2.0, 0.5) { |x| })
begin
  s = ["a", nil][0]
  s.step(3) { |i| p i }
rescue NoMethodError => e
  puts e.message
end
def total(v)
  t = 0
  v.step(10, 2) { |i| t += i }
  t
end
p total([4, nil][0])
