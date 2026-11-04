# A String whose bytes are a builder's buffer, held in a `const char *` slot
# while the handle that owns the buffer sits only in a temporary array. Each
# loop counts wrong reads over 200 turns; the churn in between allocates.
# On 129f3323 the loops print 7, 7, 6 and 8 in the plain build, and under
# SPINEL_GC_STRESS=1 the run dies with a segmentation fault before printing
# anything (three runs each). It should print four zeros.
def churn
  a = []
  60.times { |i| a << "c#{i}" << ("m#{i}".dup << "x") }
  a.size
end

# the builder's buffer comes back through `to_s` on the array element
def acarrier(k)
  s = +"h"
  3.times { s << "p#{k}" }
  [s, 7]
end

# a String operand that allocates before it answers
def cstr(k)
  churn
  "z#{k}"
end

n = 200

# an interpolation operand, with a later operand that allocates
w = 0
n.times { |k| v = "#{acarrier(k)[0]}-#{cstr(k)}"; w += 1 unless v == "hp#{k}p#{k}p#{k}-z#{k}" }
p w

# a value object's String field
class Pt
  attr_reader :s, :k
  def initialize(s, k); @s = s; @k = k; end
end
w = 0
n.times { |k| pt = Pt.new(acarrier(k)[0].to_s, k); churn; w += 1 unless pt.s == "hp#{k}p#{k}p#{k}" }
p w

# the left operand of +, with a right operand that allocates
w = 0
n.times { |k| v = acarrier(k)[0].to_s + cstr(k); w += 1 unless v == "hp#{k}p#{k}p#{k}z#{k}" }
p w

# a method argument, with a later argument that allocates
def two(a, b); a + b; end
w = 0
n.times { |k| v = two(acarrier(k)[0].to_s, cstr(k)); w += 1 unless v == "hp#{k}p#{k}p#{k}z#{k}" }
p w
