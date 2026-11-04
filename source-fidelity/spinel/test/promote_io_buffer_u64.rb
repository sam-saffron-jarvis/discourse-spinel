# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# IO::Buffer's u64 lane under --int-overflow=promote: values above 2^63-1
# come back as Bignums (and go in as them), s64 covers INT64_MIN, and the
# iteration surface carries the boxed values through. Only meaningful in
# promote mode (the literals exceed sp_int in raise/wrap).
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
b = IO::Buffer.new(16)
try("u64 max-1") { b.set_value(:u64, 8, 0xffff_ffff_ffff_fffe); b.get_value(:u64, 8) }
try("u64 2**63") { b.set_value(:u64, 0, 2**63); b.get_value(:u64, 0) }
try("u64 rt class") { v = b.get_value(:u64, 0); [v, v.class.to_s] }
try("u64 arith") { b.get_value(:u64, 0) + 1 }
try("U64 BE") { b.set_value(:U64, 0, 2**63 + 5); (0..7).map { |i| b.get_value(:U8, i) } }
try("U64 read") { b.get_value(:U64, 0) }
try("u64 -1") { b.set_value(:u64, 0, -1); b.get_value(:u64, 0) }
try("u64 small") { b.set_value(:u64, 0, 7); v = b.get_value(:u64, 0); [v, v.class.to_s] }
try("u64 2**64") { b.set_value(:u64, 0, 2**64) }
try("u64 -2**63-1") { b.set_value(:u64, 0, -(2**63) - 1) }
try("s64 big") { b.set_value(:s64, 0, 2**63) }
try("s64 -2**63") { b.set_value(:s64, 0, -(2**63)); b.get_value(:s64, 0) }
try("values u64") { b.set_value(:u64, 0, 2**63 + 9); b.set_value(:u64, 8, 3); b.values(:u64) }
try("get_values u64") { b.get_values([:u64, :s64], 0) }
try("each u64") { acc = []; b.each(:u64) { |o, v| acc << [o, v] }; acc }
