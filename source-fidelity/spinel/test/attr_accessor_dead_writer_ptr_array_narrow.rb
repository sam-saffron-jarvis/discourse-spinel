# A class DECLARING a writer for an ivar no longer keeps that ivar's array
# boxed; only a route that actually INVOKES the writer does.
#
# narrow_object_arrays used to skip any ivar whose class declared a writer,
# so one `attr_accessor` in a list of field names cost the narrowing -- even
# though the setter is never called and spinel does not emit it. A method
# absent from the output must not change the output's types.
#
# Rows below: @t narrows to sp_PtrArray (of sp_IntArray*) because nothing
# calls `t=`; @u stays sp_PolyArray because something does. Both must behave.

class Narrowed              # writer declared, never called -> sp_PtrArray *
  attr_accessor :t
  def initialize(n)
    @t = Array.new(n) { Array.new(0, 0) }
  end
  def fill
    k = 0
    while k < @t.length
      row = @t[k]
      j = 0
      while j < 3
        row << k * 10 + j
        j += 1
      end
      k += 1
    end
  end
end

nw = Narrowed.new(3)
nw.fill
p nw.t.length
p nw.t[0]
p nw.t[2]
p nw.t[1][2]
row = nw.t[1]
p row.first
p row.last
nw.t[2] = [7, 8, 9]
p nw.t[2]
nw.t << [1, 1, 1]
sum = 0
nw.t.length.times { |k| sum += nw.t[k][0] }
p sum

# an object array behind a declared-but-uncalled writer narrows the same way
class Cell
  attr_reader :v
  def initialize(v)
    @v = v
  end
end
class Holder
  attr_accessor :cells
  def initialize(n)
    @cells = Array.new(n) { |i| Cell.new(i + 1) }
  end
end
h = Holder.new(4)
tot = 0
h.cells.length.times { |i| tot += h.cells[i].v }
p tot
p h.cells[3].v

# --- the writer routes: each one must keep its ivar on the boxed path, and
#     each must still store and read back exactly what Ruby stores ---

class Assigned
  attr_accessor :u
  def initialize
    @u = Array.new(1) { Array.new(1, 0) }
  end
end

a = Assigned.new
a.u = [[1, 2], "a string, not an array"]
p a.u[0][1]
p a.u[1]
p a.u.length

b = Assigned.new
b.u ||= [[5]]
p b.u[0][0]
c = Assigned.new
c.u &&= [[6], [7]]
p c.u.length
p c.u[1][0]

d = Assigned.new
d.send(:u=, [[8], :sym])
p d.u[0][0]
p d.u[1]

e = Assigned.new
e.u, extra = [[9]], 99
p e.u[0][0]
p extra

# a writer called from another class reaches the same ivar
class Writer
  def apply(o)
    o.u = [[3], nil, 4.5]
  end
end
f = Assigned.new
Writer.new.apply(f)
p f.u[0][0]
p f.u[1]
p f.u[2]
