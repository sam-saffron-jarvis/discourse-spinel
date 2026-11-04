# A nested numeric table walked by each / each_with_index / zip / map / reduce
# keeps its rows. The block receives the row, not a boxed copy of it.
def mul(a, b)
  n = a.length
  c = Array.new(n) { Array.new(n, 0.0) }
  c.each_with_index do |ci, i|
    ai = a[i]
    b.each_with_index do |bj, j|
      s = 0.0
      ai.zip(bj) { |av, bv| s += av * bv }
      ci[j] = s
    end
  end
  c
end

a = [[1.0, 2.0], [3.0, 4.0]]
b = [[5.0, 6.0], [7.0, 8.0]]
# Index the result. Printing the table itself is an escape, and the narrow
# pass then leaves `c` boxed even though the caller only wants its rows.
m = mul(a, b)
p m[0]
p m[1]

rows = [[1, 2, 3], [4, 5, 6]]
s = 0
rows.each { |r| s += r[0] + r.length }
p s
p rows.map { |r| r[1] }
p rows.reduce(0) { |acc, r| acc + r[2] }
acc = 0
other = [[10], [20]]
rows.zip(other) { |r, o| acc += r[0] + o[0] }
p acc
rows.each_with_index { |r, i| s += r[i] }
p s

frows = [[1.5, 2.5], [3.5, 4.5]]
fs = 0.0
frows.each { |r| fs += r[0] }
p fs
frows.reverse_each { |r| fs += r[1] }
p fs

# Splitting the row (`|a, b|`, or `|a, b, c|` when the row is short) binds
# each element, including a missing one. The pointer-array walk stores one
# row pointer in the first parameter, so this shape is answered by the poly
# each until that walk learns to split the row.
split_rows = [[1, 2], [3, 4]]
split_s = 0
split_rows.each { |a, b| split_s += a + b }
p split_s
split_rows.each { |a, b, c| split_s += a }
p split_s
split_frows = [[1.5, 2.5], [3.5, 4.5]]
split_fs = 0.0
split_frows.reverse_each { |a, b| split_fs += a + b }
p split_fs
