# Thirteen shapes through ten Array arms that pass the receiver straight
# into a C call beside an argument, where the argument allocates:
# include?/member? on Integer, String and Float arrays, delete (plain and
# with a block), index, rindex, sum(init) on Integer and String arrays,
# count(v), flatten(depth) and pack(fmt). The receiver is a fresh array held
# by nothing else, so the allocation in the argument could free it. On
# 71939bdb the Integer-array loops below count wrong results in 2 of 200 in
# the plain build (pack 4, the poly flatten 8) and in 200 of 200 under
# SPINEL_GC_STRESS=1 (pack 193); the String-array and Float-array loops
# crash in both builds. Each loop prints how many of its 200 runs were wrong.
class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end

def churn
  (1..60).map { |i| [K.new(i), "s#{i}"] }
  (1..30).map { |i| [i, i.to_s] }
  (1..30).map { |i| i * 2 }
  (1..30).map { |i| "t#{i}" }
  nil
end

def ints = (1..40).map { |i| i * 10 }
def floats = (1..40).map { |i| i * 1.5 }
def strs = (1..40).map { |i| "s#{i}" }
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }

n = 200
w = 0; n.times { w += 1 unless ints.include?((churn; 100)) }; p w
w = 0; n.times { w += 1 unless strs.member?((churn; "s5")) }; p w
w = 0; n.times { w += 1 unless floats.include?((churn; 4.5)) }; p w
w = 0; n.times { w += 1 unless ints.delete((churn; 100)) == 100 }; p w
w = 0; n.times { w += 1 unless strs.delete((churn; "s5")) == "s5" }; p w
w = 0; n.times { w += 1 unless ints.index((churn; 100)) == 9 }; p w
w = 0; n.times { w += 1 unless strs.rindex((churn; "s10")) == 9 }; p w
w = 0; n.times { w += 1 unless ints.sum((churn; 5)) == 8205 }; p w
w = 0; n.times { w += 1 unless strs.sum((churn; "x"))[0, 6] == "xs1s2s" }; p w
w = 0; n.times { w += 1 unless ints.count((churn; 100)) == 1 }; p w
w = 0; n.times { w += 1 unless polys.flatten((churn; 1))[0, 3] == [10, "s2", 30] }; p w
w = 0; n.times { w += 1 unless ints.pack((churn; "C*")).bytes[0, 3] == [10, 20, 30] }; p w
w = 0; n.times { w += 1 unless ints.delete((churn; 100)) { 0 } == 100 }; p w
