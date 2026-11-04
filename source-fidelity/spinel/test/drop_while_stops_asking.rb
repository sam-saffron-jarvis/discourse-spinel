# drop_while runs its block for the dropped prefix and the first kept element
# only; every element after that is kept without asking. All three loops
# (a typed array, a poly receiver, a Hash) ran the block to the end, so a
# block with a side effect saw every element.
out = []
p [3, 1, 2].drop_while { |e| out << e; e > 1 }
p out

x = [[3, 1, 2], nil][0]
out = []
p x.drop_while { |e| out << e; e > 1 }
p out

h = { a: 3, b: 1, c: 2 }
out = []
p h.drop_while { |k, v| out << k; v > 1 }
p out

def dw(a) = a.drop_while { |e| e > 1 }
p dw([[3, 1, 2], nil][0])
p [3, 1, 2].drop_while { |e| e > 5 }
p [3, 1, 2].drop_while { |e| e > 0 }
p x.drop_while { |e| e > 5 }
p x.drop_while { |e| e > 0 }
