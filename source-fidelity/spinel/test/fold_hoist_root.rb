# Nine more hoists in the fold file copy their receiver into a C temporary
# and read it again on every turn -- as the loop bound, or as the container the
# element comes out of -- while the block between two turns allocates. Every
# receiver here is a method's answer, so nothing but that temporary holds it,
# and every block allocates before it looks at what it was given: a receiver
# collected mid-walk shows up as a short count, an empty answer or a crash,
# never as a passing test. The local-receiver arms are the control: a local is
# itself a root, so those were always safe. The with_index chain also rebinds
# its accumulator to a fresh answer every turn, and that slot is rooted here
# as the reduce emitter's already is.

ENTRIES = 40
CHURN = 100

def churn
  CHURN.times { "q" * 64 }
end

def make_array
  (1..ENTRIES).map { |i| "a#{i}" }
end

def make_ints
  (1..ENTRIES).map { |i| i.odd? ? i : i + 100 }
end

# --- each_slice(n).map, each_cons(n).map, each_cons(n).with_index.map ---

n = 0
r = make_array.each_slice(2).map { |w| churn; n += 1; w.size }
puts "each_slice map n=#{n} out=#{r.size}"

n = 0
r = make_array.each_slice(3).map { |a, b, c| churn; n += 1; "#{a}#{b}#{c}" }
puts "each_slice map params n=#{n} out=#{r.size} last=#{r.last}"

n = 0
r = make_array.each_cons(2).map { |w| churn; n += 1; w.size }
puts "each_cons map n=#{n} out=#{r.size}"

n = 0
r = make_array.each_cons(2).map { |a, b| churn; n += 1; a + b }
puts "each_cons map params n=#{n} out=#{r.size} last=#{r.last}"

n = 0
r = make_array.each_cons(2).with_index.map { |w, i| churn; n += 1; w.size + i }
puts "each_cons with_index map n=#{n} out=#{r.size} last=#{r.last}"

n = 0
r = make_array.each_cons(2).with_index(1).map { |(a, b), i| churn; n += 1; "#{a}#{b}#{i}" }
puts "each_cons with_index offset map n=#{n} out=#{r.size} last=#{r.last}"

# --- slice_when, chunk ---

n = 0
r = make_ints.slice_when { |a, b| churn; n += 1; b != a + 1 }.to_a.inspect
puts "slice_when n=#{n} len=#{r.length}"

n = 0
r = make_ints.chunk { |x| churn; n += 1; x % 2 }.to_a.inspect
puts "chunk n=#{n} len=#{r.length}"

# --- max / min / minmax with a comparator block ---

n = 0
r = make_array.max { |x, y| churn; n += 1; x <=> y }
puts "max n=#{n} r=#{r.inspect}"

n = 0
r = make_array.min { |x, y| churn; n += 1; x <=> y }
puts "min n=#{n} r=#{r.inspect}"

r = make_ints.minmax { |x, y| churn; x <=> y }
puts "minmax r=#{r.inspect}"

# --- sort! with a comparator block ---

n = 0
r = make_array.sort! { |x, y| churn; n += 1; x <=> y }
puts "sort! size=#{r.size} first=#{r.first.inspect} last=#{r.last.inspect}"

n = 0
r = make_ints.sort! { |x, y| churn; n += 1; y <=> x }
puts "sort! ints size=#{r.size} first=#{r.first} last=#{r.last}"

# --- sum(seed) with a block on the String, Integer and Float accumulators ---

n = 0
r = make_array.sum("") { |x| churn; n += 1; x }
puts "sum string n=#{n} len=#{r.length}"

n = 0
r = make_ints.sum(0) { |x| churn; n += 1; x }
puts "sum int n=#{n} r=#{r}"

n = 0
r = make_ints.sum(0.5) { |x| churn; n += 1; x }
puts "sum float n=#{n} r=#{r}"

# --- each.with_index(off).inject: the receiver, then the accumulator ---

n = 0
r = make_array.each.with_index(1).inject("z") { |acc, (x, i)| churn; n += 1; acc }
puts "with_index inject n=#{n} r=#{r.inspect}"

n = 0
r = make_array.each.with_index(1).inject("z") { |acc, (x, i)| churn; n += 1; acc + x }
puts "with_index inject string acc n=#{n} len=#{r.length}"

n = 0
ri = make_ints.each.with_index(1).inject(0) { |acc, (v, j)| churn; n += 1; acc + v + j }
puts "with_index inject int acc n=#{n} r=#{ri}"

# --- controls: the same walks over a receiver held in a local ---

held = make_array
n = 0
r = held.each_cons(2).map { |w| churn; n += 1; w.size }
puts "control each_cons map n=#{n} out=#{r.size}"

held = make_array
n = 0
r = held.max { |x, y| churn; n += 1; x <=> y }
puts "control max n=#{n} r=#{r.inspect}"

held = make_array
n = 0
r = held.sort! { |x, y| churn; n += 1; x <=> y }
puts "control sort! size=#{r.size} first=#{r.first.inspect}"
