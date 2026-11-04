#!/usr/bin/env ruby
# String#split(nil, n): the literal nil separator is discarded by the
# poly-receiver codegen, the runtime's whitespace branch in
# sp_str_split_limit is reached, the limit is honored. Regression for
# codegen_call_recv.c poly-receiver String#split arm raising
# "no implicit conversion of nil into String" on a nil-typed sep.
r = "a b c".split(nil, 2)
want = ["a", "b c"]
if r == want
  puts "ok"
else
  warn "FAIL: r=#{r.inspect}"
  exit 1
end
