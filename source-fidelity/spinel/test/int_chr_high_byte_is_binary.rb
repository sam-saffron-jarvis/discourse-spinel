# Integer#chr answers a BINARY byte above 7-bit, as CRuby does: 200.chr is
# ASCII-8BIT and only 0..127 come back on the text side. The tag is not
# cosmetic -- equal bytes are equal strings only when the encodings are
# comparable, so a string built from #chr and one read back from a file held
# the same bytes and answered `==` false. Found round-tripping every byte
# value through the zlib package.
# 0..127: CRuby answers US-ASCII, spinel the text side. spinel has two
# encodings on purpose (docs/limitations.md), and a 7-bit string is
# comparable to everything either way, so only the high half is pinned here.
p 128.chr.encoding.to_s
p 255.chr.encoding.to_s
p 65.chr
p 127.chr.bytes

bin = (0..255).map { |i| i.chr }.join
p bin.bytesize
p bin.encoding.to_s

# The comparison the tag decides: the same bytes from another binary source.
copy = bin.dup
p copy == bin
p bin.b == bin

begin
  256.chr
  puts "no raise"
rescue RangeError => e
  puts e.message
end
