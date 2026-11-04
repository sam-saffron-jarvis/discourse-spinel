# A user class's own inject / reduce, handed a block by name through an
# intermediate method: the `&b` stays a block argument. The rewrite that
# turns `arr.inject(&b)` into a fold block for the C emitters used to take
# it too, splicing `b.call` into the user method's body from a frame that
# no longer had `b` ('lv_b' undeclared). An Array keeps the rewrite; a
# receiver that may be either (poly) is not covered here.
class Acc
  def initialize(*xs) = @xs = xs
  def inject(init = nil, &b)
    r = init
    @xs.each { |x| r = r.nil? ? x : b.call(r, x) }
    r
  end
  def reduce(&b) = inject(&b)
end
def via(a, &b) = a.inject(&b)
def via2(a, &b) = a.reduce(&b)
p via(Acc.new(1, 2, 3)) { |s, x| s + x }
p via2(Acc.new(1, 2, 3)) { |s, x| s * x }
p Acc.new(4, 5).inject { |s, x| s - x }
p Acc.new(4, 5).inject(10) { |s, x| s - x }
add = ->(s, x) { s + x }
p Acc.new(1, 2).inject(&add)
p [1, 2, 3].inject(&add)
