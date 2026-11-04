# An inline-only method (a yield, or an &blk used only by .call/.nil?) has no
# function of its own; the cls_id switch reaches it through its proc form.

# a block reaches the inline-only override through the dispatch
class A
  def m(x) = x + 1
  def run = m(1)
  def run_blk = m(2) { |v| v * 100 }
end
class C < A
  def m(x, &blk) = blk.nil? ? "C#{x}" : blk.call(x).to_s
end
p A.new.run
p C.new.run
p C.new.run_blk

# a yielding override
class D
  def m(x) = x + 1
  def run = m(1)
end
class E < D
  def m(x) = block_given? ? yield(x) : x * 10
end
p D.new.run
p E.new.run

# the base is the inline-only one
class F
  def m(x, &blk) = blk.nil? ? x + 1 : blk.call(x)
  def run = m(1)
end
class G < F
  def m(x) = x * 7
end
p F.new.run
p G.new.run

# three levels, same Integer return on every arm
class H
  def m(x) = x + 1
  def run = m(3)
end
class I < H
  def m(x, &blk) = blk ? blk.call(x) : x * 2
end
class J < I
end
p H.new.run
p I.new.run
p J.new.run

# a literal block through the base-inline dispatch
class F2
  def m(x, &blk) = blk.nil? ? x + 1 : blk.call(x)
  def run = m(1)
  def run_blk = m(5) { |v| v * 3 }
end
class G2 < F2
  def m(x) = x * 7
end
p F2.new.run_blk
p G2.new.run_blk
k = 10
p [F2.new, G2.new].map { |o| o.m(2) { |v| v + k } }
