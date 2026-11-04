# A binary String keeps its bytes when it is promoted to a shared handle.
#
# Storing a String somewhere that other references can observe (an Array, a
# Hash) promotes it to a strbuf handle via sp_String_new_shared, so writes
# through one alias are seen by the rest. That constructor sized its copy with
# strlen, which stops at the first NUL -- so a binary payload arrived empty.
# `Array.new(n, 0).pack("C*")` became the zero-length string the moment it was
# stored, and the next setbyte on it raised "index 0 out of string" against a
# buffer the program had just filled. The ASCII-8BIT tag was already inherited
# here; the length was not.

n = 3

# 1. The payload survives the promotion intact -- asserted BEFORE anything is
#    written, so this is about the bytes that were already there rather than
#    about the writes below. The interior NUL is the point: sized by strlen this
#    became [1], and sized as all-NUL it became "" and the setbyte below raised
#    IndexError. The ASCII-8BIT tag has to survive with it.
kept = []
buf = [1, 0, 2].pack("C*")
kept << buf
p kept[0].bytes
p kept[0].encoding == Encoding::BINARY

# ...and setbyte through the original name still lands, with the alias in the
# container observing the writes.
i = 0
while i < n
  buf.setbyte(i, 10)
  i += 1
end
p buf.bytes
p kept[0].bytes

# 2. The promoted value has the right LENGTH when read back out and consumed by
#    another operation -- here as the right-hand side of a slice assignment,
#    which copies rhs-length bytes. A truncated handle silently wrote nothing.
dst = Array.new(n * 2, 0).pack("C*")
dst[0, n] = kept[0]
p dst.bytes

# 3. A frozen binary string still freezes. The re-fill happens while the buffer
#    is being built, before the frozen bit goes on; getting that order wrong
#    would either raise FrozenError here or lose the flag.
frozen = Array.new(n, 65).pack("C*").freeze
holder = []
holder << frozen
p holder[0].bytes
p holder[0].frozen?
