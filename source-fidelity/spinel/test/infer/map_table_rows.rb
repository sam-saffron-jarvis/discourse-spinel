# A table of rows built by `map` over another table's rows. The mapped table
# holds the SAME row objects -- `cols[k]` is not a copy -- so the two tables
# must agree on a row kind, and the mapped one can be an sp_PtrArray of row
# pointers like any other table.
#
# narrow_object_arrays had no arm for a map source, so the slot died and the
# table stayed a boxed poly array: every row was boxed on the way in and
# unboxed again on every read. The identical table built with a `while` loop
# and `<<` narrowed, so the representation depended only on which builder was
# used. The kind is an EDGE to the source table rather than element evidence,
# because the source's own kind is still being derived in the same round.
class F
  def self.mul(a, b)
    (a * b) % 97
  end
end

class View
  attr_reader :rows

  # int rows
  def load_int(n)
    cols = Array.new(n) { |c| [c, c + 1, c + 2] }
    idx = [0, 2, 3]
    @rows = idx.map { |k| cols[k] }
    nil
  end

  def total(s)
    acc = 0
    i = 0
    while i < @rows.length
      row = @rows[i]
      acc += F.mul(row[0], s)
      i += 1
    end
    acc
  end
end

v = View.new
v.load_int(4)
p v.total(3)
p v.rows[1][2]

class FView
  attr_reader :rows
  def load_f
    fsrc = Array.new(3) { Array.new(0, 0.0) }
    j = 0
    while j < 3
      fsrc[j] << (j + 0.5)
      j += 1
    end
    @rows = [0, 1].map { |k| fsrc[k] }
    nil
  end
end
fv = FView.new
fv.load_f
p fv.rows[1][0]

# The rows are shared, not copied: a push through the source table is visible
# through the mapped one.
def self.shared
  cols = Array.new(2) { Array.new(0, 0.0) }
  cols[0] << 1.0
  picked = [0, 1].map { |k| cols[k] }
  cols[0] << 2.0
  picked[0].length
end
p shared

# A HASH receiver answers the same rows, but its emitter has no pointer-array
# container to collect them into -- the hash-collect path bails on the kind and
# the fallback it drops through does not reach Hash#map at all. Narrowing this
# one stopped the program running, so the table stays boxed and this pins that.
def self.from_hash
  cols = Array.new(3) { Array.new(0, 0.0) }
  cols[0] << 1.5
  cols[1] << 2.5
  cols[2] << 3.5
  h = { 0 => 2, 1 => 0 }
  rows = h.map { |_k, vv| cols[vv] }
  [rows.length, rows[0][0], rows[1][0]]
end
p from_hash

# The un-narrow path, with a mapped table in the component: the table escapes
# somewhere the pass does not model, so the slot stays boxed. This is the path
# a stale want would be read on -- the emitter must build what the slot is.
$sink = nil
def self.escapes
  cols = Array.new(3) { |c| [c, c + 1] }
  leaked = [0, 1].map { |k| cols[k] }
  $sink = leaked
  leaked[1][0]
end
p escapes
p $sink.length

# Same, through a receiver the pass cannot resolve to one class.
class TakeA
  def take(t) = t[0][0]
end
class TakeB
  def take(t) = t[1][1]
end
def self.dispatched
  cols = Array.new(3) { |c| [c, c + 1] }
  tbl = [0, 1].map { |k| cols[k] }
  objs = [TakeA.new, TakeB.new]
  acc = 0
  i = 0
  while i < 2
    acc += objs[i].take(tbl)
    i += 1
  end
  acc
end
p dispatched
