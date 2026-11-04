# A ternary whose predicate the compiler answers statically folds to its live
# arm. That arm still has to be rendered at the WHOLE expression's type: the
# slot receiving it was declared from that type, and the arm's own may be
# narrower. Emitted raw, an `is_a?` fold put a plain string into a poly local
# and the C did not compile.

def try_conv(x)
  x.is_a?(String) ? x : nil
end

def norm(ps = nil)
  if ps.nil?
    prefix = "d"
  elsif ps.is_a?(Array)
    prefix = ps[0]                 # widens the slot to poly
  else
    # `ps` is statically a String at the only call site below, so the
    # predicate folds and this arm is all that is emitted
    prefix = ps.is_a?(String) ? ps : (try_conv(ps) or raise ArgumentError, "bad")
  end
  prefix
end

p norm("x")

# the same fold with the live arm on the else side
def pick(s = nil)
  if s.nil?
    v = 0
  else
    v = s.is_a?(Integer) ? 1 : s   # predicate folds false: the arm is `s`
  end
  v
end

p pick("str")
