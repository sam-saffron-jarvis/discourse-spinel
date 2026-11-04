# A blockless `n.times` / `a.upto(b)` / `b.downto(a)` on a BOXED Integer
# receiver -- what every Integer parameter is under --int-overflow=promote --
# keeps the range-shaped enumerator type the typed receiver has, so the chain
# on it (`.map { }`, `.to_a`, `.with_index`) is typed and emitted like the
# literal's. The receiver and an Integer limit are unboxed with the argument
# conversion; a Float limit still floors (upto) or ceils (downto).
def churn(n)
  n.times.map { |k| "x" * k }.size
end

def span(a, b)
  [a.upto(b).to_a, b.downto(a).map { |i| i * 2 }, a.times.to_a.sum]
end

def with_idx(n)
  n.times.with_index.map { |i, j| i + j }
end

def float_limits(a, b)
  [a.upto(b).to_a, 7.downto(b).to_a]
end

p churn(2)
p churn(0)
p span(2, 5)
p with_idx(3)
p float_limits(1, 3.5)
p 3.times.map { |k| k }.size
p 1.upto(3.5).to_a
p 4.downto(1.5).to_a
