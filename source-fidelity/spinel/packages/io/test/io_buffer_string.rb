# IO::Buffer get_string / set_string: NUL-embedded binary payloads, the
# four set_string arities, and the offset/length validation messages.
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
puts "== strings =="
s = IO::Buffer.new(8)
try("set") { s.set_string("abc") }
try("set off") { s.set_string("xy", 3) }
try("bytes") { s.get_string.bytes }
try("nul") { s.set_string("A\0B", 0, 3, 0); s.get_string(0, 3).bytes }
try("sub") { s.get_string(1, 3) }
try("enc") { s.get_string(0, 2).encoding.to_s }
try("4arg") { s.clear; s.set_string("abcdef", 1, 2, 3) }
try("4arg bytes") { s.get_string.bytes }
try("empty at end") { s.get_string(8) }
try("off too big") { s.get_string(9) }
try("len too big") { s.get_string(0, 9) }
try("neg len") { s.get_string(0, -1) }
try("soff big") { s.set_string("ab", 0, 1, 5) }
try("src range") { s.set_string("ab", 0, 5) }
try("buf range") { s.set_string("abcdefghi") }
try("len0") { s.set_string("ab", 0, 0) }
