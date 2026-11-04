# A block parameter keeps its scalar type where the value it binds arrives
# boxed: under --int-overflow=promote every Integer local is boxed while a
# block parameter is typed by what yields it, so a `when` lambda inlined as
# `===` over a boxed subject, and a tap / then block over a boxed receiver,
# bound an sp_RbVal to an sp_int and the C did not build. The binding unboxes
# (or boxes, the other way round) instead. Same answers in both modes.
v = 5
case v
when ->(x) { x > 3 } then puts "big"
else puts "small"
end
w = 2.5
case w
when ->(x) { x < 3.0 } then puts "low"
else puts "high"
end
def f(n)
  seen = []
  n.tap do |v|
    next if v.negative?
    seen << v
  end
  seen
end
p f(3)
p f(-3)
def g(n) = n.then { |v| v.negative? ? 0 : v * 2 }
p g(4)
p g(-4)
def h(n)
  out = 0
  n.tap { |v| out = v + 1 }
  out
end
p h(41)
