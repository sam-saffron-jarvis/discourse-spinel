# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# IO::Buffer slice invalidation and overflow-safe bounds: a view whose
# root was freed, transferred, or shrunk raises InvalidatedError (and
# answers null? false / valid? false, as CRuby does); offset+length
# checks reject huge operands instead of wrapping past the size.
B = IO::Buffer
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
a = B.new(16); s = a.slice(4, 8)
a.free
try("read after source free") { s.get_value(:U8, 0) }
try("null?") { s.null? }
try("valid?") { s.valid? }
b = B.new(16); s2 = b.slice(4, 8)
b.resize(6)
try("read after source shrink") { s2.get_value(:U8, 0) }
c = B.new(16); s3 = c.slice(4, 8)
c2 = c.transfer
try("read after source transfer") { s3.get_value(:U8, 0) }
try("get_string after free") { x = B.new(8); sl = x.slice(0,4); x.free; sl.get_string }
# overflow-safe bounds
big = 2**62
try("huge off get") { B.new(8).get_value(:u32, big) }
try("huge off+len get_string") { B.new(8).get_string(big, big) }
try("huge set_string off") { B.new(8).set_string("ab", big) }
try("huge clear") { B.new(8).clear(0, big, big) }
try("huge copy off") { d = B.new(8); d.copy(B.for("ab"), big, big) }
try("huge slice") { B.new(8).slice(big, big) }
try("huge each offset") { acc = []; B.new(8).each(:U8, big) { |o,v| acc << v }; acc }
try("valid slice still works") { q = B.new(8); q.set_string("QQQQQQQQ"); v = q.slice(2,4); q.resize(12); v.get_string }

t2 = B.new(8)
try("gs(9,0)") { t2.get_string(9, 0) }
try("ss(ab,7,5)") { t2.set_string("ab", 7, 5) }
try("copy both bad") { B.new(4).copy(B.for("ABCD"), 9, 9, 9) }
try("each off>size") { t2.each(:U8, 9) { } }
try("each off=size") { acc=[]; t2.each(:U8, 8) { |o,v| acc << v }; acc }
try("values off>size") { t2.values(:U8, 9) }
try("each neg") { t2.each(:U8, -1) { } }
