# A value-position `if`/`elsif` whose elsif arm raises and which has no
# `else`: the arm that falls through with neither condition true is the
# implicit nil, so the value is `Integer | nil`, not the `if` arm's Integer
# alone. Judging the chain by its first arm's statements typed it Integer and
# the fall-through emitted a boxed nil into an Integer slot (#4464).
def bump(x, grow, full)
  y = if grow
    x += 1
  elsif full
    raise "full"
  end
  y
end
p bump(1, true, false)
p bump(1, false, false)
begin
  bump(1, false, true)
rescue => e
  p e.message
end

# with an else, the chain has a value on every path that returns
def a(g, f)
  y = if g then 1 elsif f then raise "x" else 3 end
  y
end
p a(true, false); p a(false, false)

# every written arm raising still leaves the implicit nil
def c(g, f)
  y = if g then "s" elsif f then raise "x" elsif !f then raise "z" end
  y
end
p c(true, false)
begin
  c(false, false)
rescue => e
  p e.message
end

# a raising `if` arm with an else: the else's type
def d(g)
  y = if g then raise "q" else 5 end
  y + 1
end
p d(false)
