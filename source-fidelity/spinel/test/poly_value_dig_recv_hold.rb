# A boxed receiver of dig is held across its allocating argument.
# On fd49be64 this prints 4, 8, 0 and 5 in the plain build and 174, 26, 112
# and 100 under SPINEL_GC_STRESS=1: the receiver (a fresh array or hash a
# method answers, held by nothing else) was passed to the runtime call beside
# the argument, and an allocation after it was evaluated freed it. In the
# splat loop the argument is hoisted ahead of the receiver and the splat's
# array conversion is what allocates. CRuby prints four zeros.
# Each loop prints how many of its 200 runs were wrong.

def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  nil
end

def pv(n) = n > 0 ? (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" } : "str"
def pvn(n) = n > 0 ? (1..40).map { |i| [i, i.odd? ? i * 10 : "s#{i}"] } : "str"
def pvh(n) = n > 0 ? { "k" => [1, "v"], "j" => 2 } : "str"

n = 200
w = 0; n.times { w += 1 unless pv(1).dig((churn; 5)) == "s6" }; p w
w = 0; n.times { w += 1 unless pvn(1).dig((churn; 5), 1) == "s6" }; p w
w = 0; n.times { w += 1 unless pv(1).dig(*(churn; [5])) == "s6" }; p w
w = 0; n.times { w += 1 unless pvh(1).dig((churn; "k"), 1) == "v" }; p w
