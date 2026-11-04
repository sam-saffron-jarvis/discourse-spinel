class A
  def m(x) = x + 1
  def run = m(1)
end
class C < A
  def m(x, &blk) = blk.nil? ? "C#{x}" : "blk"
end
p A.new.run
p C.new.run
