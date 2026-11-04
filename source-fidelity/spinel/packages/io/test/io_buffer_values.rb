# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# IO::Buffer typed accessors: every type symbol, endianness, and the
# CRuby conversion edges (wrap widths, range checks, message wording).
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
puts "== value types =="
b = IO::Buffer.new(32)
%i[U8 S8 u16 s16 U16 S16 u32 s32 U32 S32 s64 S64 f32 f64 F32 F64].each do |t|
  b.set_value(t, 0, t.to_s.start_with?("f", "F") ? 1.5 : 100)
  puts "#{t}: #{b.get_value(t, 0).inspect} bytes=#{b.get_string(0, 8).bytes.inspect}"
  b.clear
end
try("wrap U8") { b.set_value(:U8, 0, 300); b.get_value(:U8, 0) }
try("wrap S8") { b.set_value(:S8, 0, 200); b.get_value(:S8, 0) }
try("wrap u16") { b.set_value(:u16, 0, -2); b.get_value(:u16, 0) }
try("wrap s16") { b.set_value(:s16, 0, 40000); b.get_value(:s16, 0) }
try("u32 -1") { b.set_value(:u32, 0, -1); b.get_value(:u32, 0) }
try("u32 hi") { b.set_value(:u32, 0, 2**32) }
try("u32 lo") { b.set_value(:u32, 0, -(2**31) - 1) }
try("s32 hi") { b.set_value(:s32, 0, 2**31) }
try("s32 lo") { b.set_value(:s32, 0, -(2**31)); b.get_value(:s32, 0) }
try("s64 min") { b.set_value(:s64, 0, -(2**62)); b.get_value(:s64, 0) }
try("f into int") { b.set_value(:u32, 0, 7.9); b.get_value(:u32, 0) }
try("int into f") { b.set_value(:f64, 0, 3); b.get_value(:f64, 0) }
try("neg off") { b.get_value(:u32, -1) }
try("oob") { b.get_value(:u32, 30) }
try("oob set") { b.set_value(:S8, 32, 1) }
try("bad type") { b.get_value(:u8, 0) }
try("nil value") { b.set_value(:u32, 0, nil) }
try("str value") { b.set_value(:u32, 0, "x") }
puts "== endianness =="
b.set_value(:u32, 0, 0x11223344)
puts (0..3).map { |i| b.get_value(:U8, i) }.inspect
b.set_value(:U32, 4, 0x11223344)
puts (4..7).map { |i| b.get_value(:U8, i) }.inspect
b.set_value(:F32, 8, 1.0)
puts (8..11).map { |i| b.get_value(:U8, i) }.inspect
