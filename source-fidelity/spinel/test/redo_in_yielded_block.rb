# redo in a block a method yields to re-runs that block with the same
# arguments: a yield outside any loop, and one after the loop's own work
def two
  yield 1
  yield 2
end
n = 0
two do |x|
  n += 1
  redo if x == 1 && n < 3
  p [x, n]
end
def pushes(xs)
  buf = []
  xs.each do |x|
    buf << x
    yield buf.size
  end
  buf
end
m = 0
p(pushes([5, 6]) do |k|
  m += 1
  redo if m == 1
  p [k, m]
end)
