# IO::Buffer construction flags, resize, clear, and copy -- including the
# readonly refusals and the CRuby bounds messages. Addresses in rendered
# headers are redacted (they differ run to run).
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
def red(s)
  s.gsub(/0x[0-9a-f]+/, "0xX")
end
puts "== new/flags =="
try("default size") { IO::Buffer.new.size }
try("small flags") { red(IO::Buffer.new(8).to_s) }
try("null") { b = IO::Buffer.new(0); [b.null?, b.empty?, b.valid?, red(b.to_s)] }
try("explicit") { red(IO::Buffer.new(8, IO::Buffer::INTERNAL | IO::Buffer::READONLY).to_s) }
try("bad flags") { IO::Buffer.new(8, 0) }
try("external") { IO::Buffer.new(8, IO::Buffer::EXTERNAL) }
try("neg size") { IO::Buffer.new(-1) }
try("ro write") { IO::Buffer.new(8, 130).set_value(:U8, 0, 1) }
try("ro set_string") { IO::Buffer.new(8, 130).set_string("a") }
try("ro clear") { IO::Buffer.new(8, 130).clear }
puts "== resize =="
r = IO::Buffer.new(8); r.set_string("ABCDEFGH")
try("grow") { r.resize(12); r.get_string.bytes }
try("shrink") { r.resize(4); r.get_string }
try("zero") { r.resize(0); [r.size, r.null?] }
try("regrow") { r.resize(4); r.get_string.bytes }
try("neg") { r.resize(-2) }
puts "== clear =="
c = IO::Buffer.new(8)
try("clear v") { c.clear(0x41); c.get_string }
try("clear v,o") { c.clear(0x42, 5); c.get_string }
try("clear v,o,l") { c.clear(0x43, 2, 2); c.get_string }
try("clear wrap") { c.clear(256 + 0x44); c.get_string(0, 1) }
try("clear -1") { c.clear(-1); c.get_string(0, 1).bytes }
try("clear oob") { c.clear(0, 6, 4) }
try("self") { c.clear.equal?(c) }
puts "== copy =="
src = IO::Buffer.new(8); src.set_string("ABCDEFGH")
try("copy") { d = IO::Buffer.new(8); [d.copy(src), d.get_string] }
try("copy o") { d = IO::Buffer.new(12); d.copy(src, 2); d.get_string.bytes }
try("copy o,l") { d = IO::Buffer.new(8); d.copy(src, 1, 3); d.get_string.bytes }
try("copy o,l,so") { d = IO::Buffer.new(8); d.copy(src, 1, 3, 4); d.get_string.bytes }
try("overlap") { o = IO::Buffer.new(8); o.set_string("ABCDEFGH"); o.copy(o, 2, 4, 0); o.get_string }
try("dst oob") { IO::Buffer.new(4).copy(src) }
try("src oob") { IO::Buffer.new(16).copy(src, 0, 6, 4) }
try("string src") { IO::Buffer.new(4).copy("ab") }
try("int src") { IO::Buffer.new(4).copy(42) }
try("ro dst") { IO::Buffer.new(8, 130).copy(src) }
