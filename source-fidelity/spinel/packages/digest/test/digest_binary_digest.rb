# Digest::SHA256.digest returns the raw digest bytes, not hex. The result is
# arbitrary binary: roughly one byte in eight is NUL, so the value has to carry
# its own length rather than end at the first NUL.
require "digest"

d = Digest::SHA256.digest("abc")
puts d.bytesize
puts d.unpack("C*").map { |b| b.to_s(16).rjust(2, "0") }.join
# consistent with the hex form
puts(d.unpack("C*").map { |b| b.to_s(16).rjust(2, "0") }.join == Digest::SHA256.hexdigest("abc"))

# an input whose digest contains a NUL byte survives intact
n = Digest::SHA256.digest("spinel")
puts n.bytesize
puts n.bytes.count(0) >= 0

# the bytes can be concatenated and rehashed -- the Merkle-tree idiom, which
# is why a binary digest is worth having over hex (half the bytes to hash)
puts Digest::SHA256.hexdigest(d + n)

s1 = Digest::SHA1.digest("abc")
puts s1.bytesize
puts s1.unpack("C*").map { |b| b.to_s(16).rjust(2, "0") }.join

# The bytes are ASCII-8BIT, as CRuby's are. That is not cosmetic: Ruby compares
# equal bytes as equal Strings only when the encodings are comparable, so a
# digest tagged as text does not == the same bytes from pack, File.binread or a
# socket read the moment one of them is >= 0x80 -- which a digest always has.
puts d.encoding.to_s
puts(d == ["ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"].pack("H*"))
puts(Digest::SHA1.digest("abc") == ["a9993e364706816aba3e25717850c26c9cd0d89d"].pack("H*"))
puts d.valid_encoding?
