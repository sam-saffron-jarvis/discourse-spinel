# Fourteen shapes through twelve more Array arms that pass their receiver
# straight into the runtime call beside an argument that allocates. On
# 2ceceddb six of the loops below crash in the plain build (the `strs * sep`
# join, the Integer-array `combination`, the three String-array needles and
# the Float-array `sum`) and the other eight count wrong results in 2 to 14
# of 200; under `SPINEL_GC_STRESS=1` five of the six still crash, the
# `combination` loop counts 200 of 200 and the others count 150 to 200 of
# 200. Each arm now holds its receiver, rooted, across the argument.
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
def pneedle(n) = n.odd? ? n * 10 : "s#{n}"
def i5; 5; end

n = 200
w = 0; n.times { w += 1 unless (strs * (churn; "-"))[0, 9] == "s1-s2-s3-" }; p w
w = 0; n.times { w += 1 unless ints.combination((churn; 2)).first == [10, 20] }; p w
w = 0; n.times { w += 1 unless ints.dig((churn; 5)) == 60 }; p w
w = 0; n.times { w += 1 unless polys.dig((churn; 5)) == "s6" }; p w
w = 0; n.times { w += 1 unless ints[i5..(churn; i5 + 2)] == [60, 70, 80] }; p w
w = 0; n.times { w += 1 unless polys[i5..(churn; i5 + 1)] == ["s6", 70] }; p w
w = 0; n.times { w += 1 unless strs.include?((churn; pneedle(6))) }; p w
w = 0; n.times { w += 1 unless strs.index((churn; pneedle(6))) == 5 }; p w
w = 0; n.times { w += 1 unless strs.rindex((churn; pneedle(6))) == 5 }; p w
w = 0; n.times { w += 1 unless floats.sum((churn; 0.5)) == 1230.5 }; p w
w = 0; n.times { w += 1 unless polys.delete((churn; "s2")) == "s2" }; p w
w = 0; n.times { w += 1 unless polys.delete((churn; "s2")) { 0 } == "s2" }; p w
w = 0; n.times { w += 1 unless polys.rindex((churn; "s2")) == 1 }; p w
w = 0; n.times { w += 1 unless polys.include?((churn; "s2")) }; p w
