# `to_h` with a block on a boxed Hash or Array compiled to an unconditional
# NoMethodError naming the class that defines it (#4838).

P = { a: { 1 => [0.5], 2 => [1.5] } }.freeze
p P.fetch(:a).to_h { |k, v| [k, v.sum * 2] }
p P[:a].to_h { |k, v| [k, v.sum * 2] }
x = [{ 1 => 2 }, 1][0]
p x.to_h { |k, v| [k, v * 2] }
y = [[1, 2, 3], 1][0]
p y.to_h { |e| [e, e * 2] }
p x.to_h
z = [[[1, 2], [3, 4]], 1][0]
p z.to_h
p z.to_h { |a, b| [b, a] }
h = { 1 => 2 }
p h.to_h { |k, v| [v, k] }
