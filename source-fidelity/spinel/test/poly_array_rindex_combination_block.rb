# rindex { } and combination / permutation / repeated_* with a block on an
# Array of mixed classes walk the boxed elements, as they do on an Integer
# array (#4919).
a = [1, "a", :b, 3]
p a.rindex { |x| x == :b }
p a.rindex { |x| x.is_a?(Integer) }
p a.rindex { |x| x == :none }
i = a.rindex { |x| x == "a" }
p i + 1 if i
r = []
a.combination(1) { |c| r << c }
p r
n = 0
a.combination(2) { |c| n += c.size }
p n
q = []
[1, "x"].permutation { |c| q << c }
p q
t = []
[:p, 2].repeated_combination(2) { |c| t << c }
p t
u = 0
[:p, 2].repeated_permutation(2) { |c| u += 1 }
p u
