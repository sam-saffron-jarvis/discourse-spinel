# String#encode with a source encoding and the invalid:/undef:/replace:
# keywords: the runtime models UTF-8 and ASCII-8BIT, so a transcode is one
# of four pairs. Same encoding keeps the bytes (scrubbed under invalid:
# :replace); binary to UTF-8 and back refuses every byte or character
# outside ASCII with Encoding::UndefinedConversionError, or replaces it under
# undef: :replace (U+FFFD for a UTF-8 target, "?" otherwise, or `replace:`).
# The three-argument form was NoMethodError, and the two-argument binary to
# UTF-8 form kept bytes it should have refused. (#4439)
s = "Hello \xC3\xA2\xC2\x80\xC2\x99World"
p s.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
p s.encode("UTF-8", "binary", undef: :replace, replace: "?")
p "plain".encode("UTF-8", "binary")
begin
  p "caf\xC3\xA9".encode("UTF-8", "binary")
rescue Encoding::UndefinedConversionError => e
  puts "#{e.class}: #{e.message}"
end
p s.encode("UTF-8").bytesize
p s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").bytesize
p "caf\xC3\xA9".encode("binary", undef: :replace)
begin
  "caf\xC3\xA9".encode("ASCII-8BIT")
rescue EncodingError => e
  puts "#{e.class}: #{e.message}"
end
p "bad\xFFbyte".encode("UTF-8", invalid: :replace, replace: "*")
p "caf\xC3\xA9".b.encode("UTF-8", undef: :replace)
p "abc".encode(Encoding::BINARY).encoding.to_s
p "abc".encode(Encoding::UTF_8, Encoding::BINARY)
v = ["x\xC3\xA9"].first
p v.encode("UTF-8", "binary", undef: :replace, replace: "_")
