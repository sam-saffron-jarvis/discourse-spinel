# IO::Buffer comparison (byte-lexicographic <=>, TypeError on non-buffer
# operands), the tiling bitwise family, and IO::Buffer.for/.string/.size_of.
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
def red(s)
  s.gsub(/0x[0-9a-f]+/, "0xX")
end
puts "== cmp =="
fa = IO::Buffer.for("AB")
try("eq") { fa == IO::Buffer.for("AB") }
try("ne size") { fa == IO::Buffer.for("ABC") }
try("ne bytes") { fa == IO::Buffer.for("AC") }
try("neq op") { fa != IO::Buffer.for("AC") }
try("cmp") { [fa <=> IO::Buffer.for("AC"), fa <=> IO::Buffer.for("AB"), IO::Buffer.for("b") <=> IO::Buffer.for("a")] }
try("prefix") { [fa <=> IO::Buffer.for("ABC"), IO::Buffer.for("ABC") <=> fa] }
try("empty") { IO::Buffer.new(0) <=> fa }
try("eq string") { fa == "AB" }
try("cmp nil") { fa <=> nil }
puts "== for/string =="
try("for flags") { red(IO::Buffer.for("hi").to_s) }
try("for empty") { b = IO::Buffer.for(""); [b.size, b.null?, red(b.to_s)] }
try("for ro") { IO::Buffer.for("hello").set_value(:U8, 0, 1) }
try("for resize") { IO::Buffer.for("hello").resize(10) }
try("for dup write") { d = IO::Buffer.for("hello").dup; d.set_string("HELLO"); d.get_string }
try("for bytes") { IO::Buffer.for("A\0B").get_string.bytes }
try("string") { IO::Buffer.string(5) { |bb| bb.set_string("HELLO") } }
try("string enc") { IO::Buffer.string(2) { |bb| }.bytes }
try("string ret") { IO::Buffer.string(3) { |bb| 99 } }
try("size_of") { [IO::Buffer.size_of(:U8), IO::Buffer.size_of(:u64), IO::Buffer.size_of([:U8, :u32])] }
try("size_of bad") { IO::Buffer.size_of(:u9) }
puts "== bitwise =="
x = IO::Buffer.for("\x0f\xf0\xaa")
y = IO::Buffer.for("\x33\x33\x33")
try("and") { (x & y).get_string.bytes }
try("and flags") { red((x & y).to_s) }
try("or") { (x | y).get_string.bytes }
try("xor") { (x ^ y).get_string.bytes }
try("not") { (~x).get_string.bytes }
try("mismatch") { (IO::Buffer.for("\xff") & y).get_string.bytes }
try("and!") { m = IO::Buffer.for("\xff\xff\xff").dup; r = m.and!(y); [r.equal?(m), m.get_string.bytes] }
try("or!") { m = IO::Buffer.new(3); m.or!(y); m.get_string.bytes }
try("xor!") { m = IO::Buffer.for("\xff\x00\xff").dup; m.xor!(y); m.get_string.bytes }
try("not!") { m = IO::Buffer.for("\x0f").dup; m.not!; m.get_string.bytes }
try("and! ro") { x.and!(y) }
try("and! smaller") { m = IO::Buffer.new(4); m.clear(9); m.and!(y); m.get_string.bytes }
try("null and") { red((IO::Buffer.new(0) & y).to_s) }
try("null not") { red(IO::Buffer.new(0).not!.to_s) }
