# A `break` in a block an iterator splices as a C loop is a same-function
# goto, and the wrapper around the call carried a serial-addressed setjmp
# scope for it all the same: one sp_brk_push and one setjmp per call, which
# is what made a Ruby-defined Enumerable#find twice the cost of its C
# emitter. The wrapper drops the scope when every break in the block is the
# goto (a typed container or Integer receiver, or an inlined yielding
# method, and no proc, nested block-taking call, begin or loop inside it);
# a boxed receiver, a user each that lifts its block, and a break behind
# a frame keep the scope. Values and control are the same either way.
a = (1..1000).to_a
r = nil
a.each { |x| if x > 998; r = x; break; end }
p r
p a.each { |x| break x * 2 if x == 3 }
p a.each { |x| break if x == 3 }
def fnd(a)
  found = nil
  a.each do |x|
    if x > 998
      found = x
      break
    end
  end
  found
end
p fnd(a)
p [7, 8].each_with_index { |x, i| break i if x == 8 }
p({ a: 1, b: 2 }.each { |k, v| break k if v == 2 })
p((1..9).each { |i| break i if i * i > 30 })
p 5.times { |i| break i * 100 if i == 3 }
def yielder(n)
  i = 0
  while i < n
    yield i
    i += 1
  end
  :done
end
p yielder(5) { |i| break i if i == 2 }
p yielder(5) { |i| i }
# these keep the setjmp scope
class Bag
  def initialize(*a) = @a = a
  def each(&b) = @a.each(&b)
end
p Bag.new(1, 2, 3).each { |x| break x * 10 if x == 2 }
def poly(v) = v
poly("s")
p poly([4, 5, 6]).each { |x| break x if x > 4 }
p [1, 2, 3].each { |x| [9].each { |y| break }; break x if x == 2 }
p [1, 2, 3].each { |x| begin; break x if x == 2; ensure; end }
p [1, 2].each { |x| pr = ->(v) { v }; break pr.call(x) if x == 2 }
def m(a) = a.each { |x| return x if x > 1 }
p m([1, 2, 3])
