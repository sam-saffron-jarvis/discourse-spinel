# IO::Buffer slices are live views (writes go through both ways, across a
# source resize); transfer moves ownership, free and dup detach.
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
def red(s)
  s.gsub(/0x[0-9a-f]+/, "0xX")
end
puts "== slice =="
a = IO::Buffer.new(16); a.set_string("ABCDEFGHIJKLMNOP")
sl = a.slice(4, 8)
try("size") { sl.size }
try("str") { sl.get_string }
try("view") { a.set_value(:U8, 4, 0x7a); sl.get_string(0, 1) }
try("write back") { sl.set_value(:U8, 1, 0x21); a.get_string(5, 1) }
try("nested") { sl.slice(2, 2).get_string }
try("flags") { red(sl.to_s) }
try("no args") { a.slice.size }
try("one arg") { a.slice(10).size }
try("oob") { a.slice(10, 10) }
try("neg") { a.slice(-1, 2) }
try("empty end") { a.slice(16, 0).size }
try("slice resize detach") { s2 = a.slice(0, 4); s2.resize(2); [red(s2.to_s), s2.get_string, a.get_string(0, 4)] }
puts "== transfer/free/dup =="
t = IO::Buffer.new(8); t.set_string("QRSTUVWX")
t2 = t.transfer
try("moved") { t2.get_string }
try("old") { [t.null?, t.valid?, t.size, t.get_string, red(t.to_s)] }
f = IO::Buffer.new(8)
try("free") { [red(f.free.to_s), f.null?, f.size] }
try("free again") { red(f.free.to_s) }
try("freed get") { f.get_value(:U8, 0) }
try("freed get_string") { f.get_string }
ro = IO::Buffer.new(4, 130)
try("dup") { d = ro.dup; [d.readonly?, red(d.to_s)] }
try("dup indep") { a2 = IO::Buffer.new(4); a2.set_string("MMMM"); d = a2.dup; d.set_string("NNNN"); [d.get_string, a2.get_string] }
try("dup null") { red(IO::Buffer.new(0).dup.to_s) }
try("clone") { ro.clone.readonly? }
