# The bundled zlib. Every answer here is CRuby's, generated from it: the point
# of the package is that a stream written by one is read by the other.
#
# What this file cannot pin is the COMPRESSED bytes -- spinel emits fixed
# Huffman where zlib builds a dynamic table, so the two agree on what a stream
# means and not on how many bytes it takes. So the assertions are round trips,
# checksums (which are exact), and the framing.
require "zlib"

# Checksums are exact, and are the cheapest thing to get subtly wrong.
p Zlib.crc32("The quick brown fox jumps over the lazy dog")
p Zlib.adler32("The quick brown fox jumps over the lazy dog")
p Zlib.crc32("")
p Zlib.adler32("")
p Zlib.crc32("abc", Zlib.crc32("hello "))
p Zlib.crc32("hello abc")

texts = [
  "",
  "a",
  "hello world",
  "abcabcabc" * 300,
  ("\x00" * 400) + ("\xff" * 400),
  (0..255).map { |i| i.chr }.join * 8,
]

# zlib framing, gzip framing, and raw deflate all round-trip.
texts.each do |s|
  z = Zlib.deflate(s)
  p Zlib.inflate(z).bytes == s.bytes
  g = Zlib.gzip(s)
  p Zlib.gunzip(g).bytes == s.bytes
  raw = Zlib::Deflate.new(6, -Zlib::MAX_WBITS).deflate(s, Zlib::FINISH)
  p Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw).bytes == s.bytes
end

# The default level is the one nearly every caller takes, and it has to be
# the one that compresses: Z_DEFAULT_COMPRESSION is -1, which is level 6.
big = "the same sentence over and over. " * 400
p Zlib.deflate(big).bytesize < big.bytesize / 4
p Zlib.deflate(big, 0).bytesize > big.bytesize / 4
p Zlib.deflate(big, 9).bytesize < big.bytesize / 4

# A binary result carries the binary tag, so it compares equal to bytes read
# back from a file rather than answering false on the encoding.
p Zlib.inflate(Zlib.deflate("plain")).encoding.to_s
p Zlib.inflate(Zlib.deflate("plain")) == "plain"

# The object forms accumulate.
d = Zlib::Deflate.new
d << "one "
d << "two "
d << "three"
p Zlib.inflate(d.finish) == "one two three"

i = Zlib::Inflate.new
i << Zlib.deflate("accumulated")
p i.finish == "accumulated"
p i.finished?

# Class-method spellings
p Zlib::Inflate.inflate(Zlib::Deflate.deflate("classy")) == "classy"

# A stream that is not one raises DataError rather than returning nonsense.
begin
  Zlib.inflate("not a deflate stream at all")
  puts "no raise"
rescue Zlib::DataError => e
  puts "DataError"
end

begin
  Zlib.gunzip("\x1f\x8b\x08\x00truncated")
  puts "no raise"
rescue Zlib::Error
  puts "Error"
end

# Truncated input is an error, not a short answer.
z = Zlib.deflate("something long enough to be cut in half safely")
begin
  Zlib.inflate(z.byteslice(0, z.bytesize / 2))
  puts "no raise"
rescue Zlib::Error
  puts "Error"
end

p Zlib::MAX_WBITS
p Zlib::BEST_COMPRESSION
p Zlib::DEFAULT_COMPRESSION
