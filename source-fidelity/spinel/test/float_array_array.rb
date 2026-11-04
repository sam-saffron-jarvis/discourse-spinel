# Array of float-arrays (TY_FLOAT_ARRAY_ARRAY): the mirror of TY_INT_ARRAY_ARRAY.
# A monomorphic array whose elements are themselves float arrays is stored
# unboxed (sp_PtrArray of sp_FloatArray*), so indexing yields a typed float
# array and the inner loop is a machine add on sp_float -- no container-kind
# dispatch, no tagged add, no GC root registration per iteration.
module Vec
  def self.scale(a, s)
    [a[0] * s, a[1] * s, a[2] * s]
  end
  def self.add(a, b)
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
  end
end

rows = []
8.times { |i| rows << [i + 0.5, i + 1.5, i + 2.5] }

acc = [0.0, 0.0, 0.0]
100.times do |t|
  c = t % 8
  acc = Vec.add(acc, Vec.scale(rows[c], t * 0.25))
end
p acc

# container ops: index, first, last, length, []=, empty?
p rows.length
p rows[0]
p rows.first
p rows.last
rows[2] = [99.5, 98.5, 97.5]
p rows[2]
p rows.empty?

# element pulled into a local, then indexed and written
row = rows[3]
p row[1]
row[1] = -1.25
p rows[3][1]
p row.length

# push more, iterate by index, accumulate as a float
rows << [10.5, 20.5, 30.5]
sum = 0.0
rows.length.times { |k| sum += rows[k][0] }
p sum

# array-of-float-array LITERAL narrows the same way a pushed one does
lit = [[1.5, 2.5], [3.5, 4.5], [5.5, 6.5]]
p lit.length
p lit[0]
p lit[2]
tot = 0.0
lit.length.times { |k| tot += lit[k][0] + lit[k][1] }
p tot

# the table as an ivar, reached through an attr_reader, and rendered by the
# object's own inspect (sp_FloatArrayPtrArray_inspect)
class Grid
  attr_reader :g
  def initialize(r, c)
    @g = Array.new(r) { Array.new(c, 0.0) }
  end
  def fill
    i = 0
    while i < @g.length
      row = @g[i]
      j = 0
      while j < row.length
        row[j] = i * 10.0 + j
        j += 1
      end
      i += 1
    end
  end
  def total
    s = 0.0
    i = 0
    while i < @g.length
      row = @g[i]
      j = 0
      while j < row.length
        s += row[j]
        j += 1
      end
      i += 1
    end
    s
  end
end
gr = Grid.new(3, 4)
gr.fill
p gr.total
p gr.g[2][3]
p gr.g.length
p gr.g[1]
p gr.inspect.gsub(/0x[0-9a-f]+/, "0xX")

# a mixed table (int rows and float rows) must NOT narrow -- two element kinds
mixed = [[1, 2], [3.5, 4.5]]
p mixed[0][0]
p mixed[1][1]
p mixed.length
