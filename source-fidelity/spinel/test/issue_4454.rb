# #4454: #3158 again, for a `{}` the CALLER also writes into. The reverse binding
# typed the local PolyPoly so the callee's writes through the reference
# persist, but the caller's own `sub["body"] = "hi"` re-derived it as a
# StrStr hash every fixpoint round; the two passes traded the slot to the
# 128-round cap, and the callee's int-keyed write was dropped.
def store(h, n)
  h[n] ||= n * 10
end
sub = {}
sub["body"] = "hi"
store(sub, 1)
store({ 2 => 3 }, 2)
p sub

# The same slot walked by a recursive reader whose parameter is poly by
# way of its own recursion.
def deep_dup(h)
  out = {}
  h.each { |k, v| out[k] = v.is_a?(Hash) ? deep_dup(v) : v }
  out
end
nested = {}
nested["a"] = { "b" => 1 }
p deep_dup(nested)
