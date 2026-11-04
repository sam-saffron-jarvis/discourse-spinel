# The value of a begin/ensure expression, and a return deferred past an
# ensure body, are rooted while the ensure body runs. Each loop below
# computes a value in a begin whose ensure body allocates, then reads the
# value. On 6c10c479 the first ten loops print zeros (#4814); the eleventh
# prints 13 in the plain build and the run dies with a segmentation fault
# under SPINEL_GC_STRESS=1 (three runs each). It should print eleven zeros.
class Bits
  attr_reader :v
  def initialize(v) @v = v end
end
def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  (1..30).map { |i| Bits.new(-i) }
  nil
end
def plain(a, b)
  return "s" if a < 0
  Bits.new(a - b)
end
def mka(n)
  return "s#{n}" if n < 0
  [1, "a", n]
end
n = 200

# a poly value with a rescue arm and an ensure body
def poly_rescue_ensure
  begin
    plain(6, (churn; 3))
  rescue => e
    e.class.to_s
  ensure
    churn
  end.v
end
w = 0; n.times { w += 1 unless poly_rescue_ensure == 3 }; p w

# a typed object with an ensure body alone
def obj_ensure
  begin
    Bits.new(3)
  ensure
    churn
  end.v
end
w = 0; n.times { w += 1 unless obj_ensure == 3 }; p w

# the rescue arm's value
def rescue_value_ensure
  begin
    raise "x"
  rescue
    plain(7, 3)
  ensure
    churn
  end.v
end
w = 0; n.times { w += 1 unless rescue_value_ensure == 4 }; p w

# a string
def str_ensure(k)
  begin
    "s#{k}"
  ensure
    churn
  end.size
end
w = 0; n.times { w += 1 unless str_ensure(12345) == 6 }; p w

# a poly array as the method's tail
def polyarr_tail_ensure
  begin
    mka(1)
  ensure
    churn
  end
end
w = 0; n.times { w += 1 unless polyarr_tail_ensure == [1, "a", 1] }; p w

# the else arm's value
def else_ensure
  begin
    1
  rescue
    plain(2, 0)
  else
    plain(5, 0)
  ensure
    churn
  end.v
end
w = 0; n.times { w += 1 unless else_ensure == 5 }; p w

# at the top level, assigned to a local
w = 0
n.times do
  r = begin
    plain(6, (churn; 3))
  ensure
    churn
  end.v
  w += 1 unless r == 3
end
p w

# a return deferred past the ensure body
def deferred_return
  begin
    return plain(6, (churn; 3))
  ensure
    churn
  end
end
w = 0; n.times { w += 1 unless deferred_return.v == 3 }; p w

# a string returned the same way
def deferred_return_str(k)
  begin
    return "s#{k}"
  ensure
    churn
  end
end
w = 0; n.times { w += 1 unless deferred_return_str(12345) == "s12345" }; p w

# a String as the tail of an inlined block
def each_once
  v = yield
  v
end
w = 0
n.times do
  r = each_once { begin; "s#{12345}"; ensure; churn; end }
  w += 1 unless r == "s12345"
end
p w

# a String whose bytes are a builder's buffer: the temp holds the buffer and
# the handle that owns it sits only in a temporary array
def acarrier(k)
  s = +"h"
  3.times { s << "p#{k}" }
  [s, 7]
end
w = 0
n.times { |k| v = begin; acarrier(k)[0].to_s; ensure; churn; end; w += 1 unless v == "hp#{k}p#{k}p#{k}" }
p w
