# The BINARY (ASCII-8BIT) tag survives the operations that cannot change what
# the bytes are: a concatenation, a join, a repeat, a slice. Ruby compares
# equal bytes as equal Strings only when the encodings are comparable, so a
# result that loses the tag stops comparing equal to the same bytes from pack,
# File.binread or a socket -- silently, and only once a byte is >= 0x80.
#
# Interpolation is NOT covered and is deliberately not asserted here: it is
# assembled inline by the emitter into one raw buffer rather than through a
# runtime function, so propagating the tag there is a codegen change on the
# hottest string path in the language and wants a benchmark, not a guess.
# "#{bin}" therefore still answers UTF-8 where CRuby answers ASCII-8BIT.
bin  = ["00ff80"].pack("H*")
bin2 = ["fe01"].pack("H*")

def e(s) = s.encoding.to_s

p [e(bin + bin2), e(bin2 + bin)]
# An ASCII-only operand adopts the other's encoding, either way round.
p [e("hdr" + bin), e(bin + "hdr")]
p e("a" + bin + "b")
p e([bin, bin2].join)
p e([bin, bin2].join("-"))
p e(bin * 3)
p e(bin.byteslice(0, 2))
p e(bin.byteslice(1))
p e(bin[0, 2])
p e(bin.dup)

# Text stays text when nothing binary is involved.
p [e("a" + "b"), e(["a", "b"].join), e("ab" * 2), e("abc".byteslice(0, 2))]

# The consequence that matters: the round trip still compares equal.
digest = ["9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"].pack("H*")
p ("" + digest) == digest
p [digest].join == digest
p digest.byteslice(0, 32) == digest
p (digest.byteslice(0, 16) + digest.byteslice(16, 16)) == digest
p ("hdr" + digest) == ("hdr".b + digest)

# An empty result still has an encoding, and it is the source's. The shared
# empty string cannot carry that -- marking it would tag it for every other
# holder of the same pointer -- so a binary source gets a fresh one, and
# nothing else pays for it.
p [bin.byteslice(0, 0).encoding.to_s, bin[0, 0].encoding.to_s,
   bin[3, 5].encoding.to_s, (bin * 0).encoding.to_s]
p ["".encoding.to_s, "abc"[0, 0].encoding.to_s, ("ab" * 0).encoding.to_s]
p ["".empty?, bin.byteslice(0, 0).empty?, (bin * 0).empty?]
