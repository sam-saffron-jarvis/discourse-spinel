# String#split with a nil separator through a POLY receiver: the arm that
# dispatches split at runtime ran emit_str_expr's nil guard on the separator
# and raised TypeError before the runtime's whitespace branch could answer
# (#4223). The literal-receiver form never took this arm, which is why it
# alone did not reproduce the report.
def pick(f)
  f ? "a  b\tc" : 7
end

v = pick(true)
p v.split(nil)
p v.split(nil, 2)
p v.split(nil, -1)

# the separator expression is still evaluated once, for its side effects
counter = 0
sep = nil
r = v.split((counter += 1; sep), 2)
p r
p counter

# a real separator through the same arm keeps its path
p v.split(" ", 2)

# a separator that is nil only at RUN TIME (a poly slot): must stay the
# whitespace mode, not stringify to "" and become a character split
x = v.length > 100 ? "," : nil
p v.split(x)
p v.split(x, 2)

# the same runtime-nil separator with a plain String receiver
s = "a  b\tc"
p s.split(x)
p s.split(x, 2)
p s.split(nil, 2)

