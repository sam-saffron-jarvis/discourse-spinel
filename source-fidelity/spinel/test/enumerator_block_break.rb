# A block that breaks out of map, select, inject, each_slice and the rest on
# an Enumerator. The calls took the receiver through to_a first, which never
# returned for an endless one, so the break never ran; each_entry,
# each_slice and each_cons answered the Enumerator even when the block broke.
e = Enumerator.new { |y| i = 0; loop { y << (i += 7) } }
p e.map { |v| break v if v > 20; v }
p e.collect { |v| break [v] if v > 20; v }
p e.select { |v| break v if v > 20; v.odd? }
p e.filter { |v| break if v > 30; v.even? }
p e.reject { |v| break v if v > 20; v.odd? }
p e.filter_map { |v| break v if v > 20; v * 2 if v.odd? }
p e.each_with_object([]) { |v, a| break a if v > 20; a << v }
p e.inject { |s, v| break s if v > 20; s + v }
p e.inject(0) { |s, v| break s if v > 20; s + v }
p e.reduce(100) { |s, v| break s if v > 20; s + v }
p e.each_slice(2) { |a| break a if a[0] > 20 }
p e.each_cons(2) { |a| break a if a[0] > 20 }
p e.with_index { |v, i| break [v, i] if v > 20 }
p e.with_index(1) { |v, i| break [v, i] if v > 20 }
p e.each_entry { |v| break v if v > 20 }
r = e.filter_map do |v|
  next if v == 14
  break v if v > 30
  v
end
p r

c = %w[a b c].cycle
p c.map { |v| break v + "!" if v == "c"; v }
p c.each_slice(2) { |a| break a.join if a[0] == "c" }

# a finite one runs to the end when the block does not break
f = [1, 2, 3].each
p f.map { |v| break 99 if v > 5; v * 3 }
p f.each_slice(2) { |a| break a if a.size > 5 }
p f.each_entry { |v| break v if v > 2 }
p f.inject { |a, v| break a if v > 5; a * v }

def gen(n) = Enumerator.new { |y| n.times { |i| y << i * i } }
p gen(5).map { |v| break :big if v > 100; v + 1 }
p gen(50).map { |v| break :big if v > 100; v + 1 }
