# IO::Buffer hexdump and inspect/to_s (addresses redacted): the 16-byte
# default layout, explicit widths, the 256-byte inspect cap, null buffers.
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
def red(s)
  s.gsub(/0x[0-9a-f]+/, "0xX")
end
puts "== hexdump/inspect =="
h = IO::Buffer.new(16)
h.set_string("Hello World!")
puts red(h.inspect)
puts red(h.to_s)
try("hexdump") { h.hexdump }
try("hexdump o,l") { h.hexdump(2, 4) }
try("hexdump w") { h.hexdump(0, 8, 4) }
try("hexdump w1") { h.hexdump(0, 3, 1) }
try("w0") { h.hexdump(0, 2, 0) }
try("neg") { h.hexdump(-1, 2) }
try("null") { IO::Buffer.new(0).hexdump }
try("null inspect") { red(IO::Buffer.new(0).inspect) }
try("empty for") { red(IO::Buffer.for("").inspect) }
big = IO::Buffer.new(300)
big.set_string("Z" * 300)
puts red(big.inspect)
