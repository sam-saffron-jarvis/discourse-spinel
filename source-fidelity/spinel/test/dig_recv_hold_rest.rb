# Seven more dig arms hold their receiver across an allocating key, one
# loop each. On 8d50f53e the first six print 2, 0, 2, 6, 3 and 4 in the
# plain build and, under SPINEL_GC_STRESS=1, 200, 112, 26, 200 and 199,
# then segfault in the sixth: the receiver (a fresh Hash, Array or Struct
# a method answers, held by nothing else) was read by the runtime call
# after a key, or the splat's array conversion, had allocated and freed
# it. The seventh loop is the Struct arm's other path, the one a member
# named at run time takes, which the six above never reach -- a
# regression there would pass all of them (it prints 200 under stress on
# the same build). CRuby prints seven zeros.
# Each loop prints how many of its 200 runs were wrong.

def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  nil
end

def hh; h = {}; (1..30).each { |i| h["k#{i}"] = i }; h; end
def hn; h = {}; (1..30).each { |i| h["k#{i}"] = [i, i * 2] }; h; end
def keys; churn; ["k5"]; end
def pa = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }
def pan = (1..40).map { |i| [i, i.odd? ? i * 10 : "s#{i}"] }
S = Struct.new(:a, :b)
def mk; S.new((1..20).map { |i| "e#{i}" }, 3); end

n = 200
w = 0; n.times { w += 1 unless hh.dig(*keys) == 5 }; p w
w = 0; n.times { w += 1 unless pa.dig(*(churn; [5])) == "s6" }; p w
w = 0; n.times { w += 1 unless pan.dig((churn; 5), 1) == "s6" }; p w
w = 0; n.times { w += 1 unless mk.dig(:a, (churn; 5)) == "e6" }; p w
w = 0; n.times { w += 1 unless mk.dig((churn; :a), (churn; 5)) == "e6" }; p w
w = 0; n.times { w += 1 unless hh.dig((churn; "k5")) == 5 }; p w
w = 0; n.times { w += 1 unless hn.dig((churn; "k5"), 1) == 10 }; p w
