# String#empty? asks for the length, not for a terminator. A NUL is an ordinary
# byte in a Ruby String: "\0abc" is four bytes long and is not empty, and a
# binary string that happens to start with one -- a digest, a packed record, a
# protocol frame with a zero-valued first field -- is not empty either.
p "\0abc".empty?
p "\0".empty?
p "".empty?
p "abc".empty?

bin = [0x00, 0x01, 0x02].pack("C*")
p [bin.bytesize, bin.empty?]
p [bin.byteslice(0, 1).bytesize, bin.byteslice(0, 1).empty?]

# The answer has to agree with the length, whichever way it comes out.
[".", "\0", "\0\0", "", "a\0b"].each do |s|
  p [s.bytesize, s.empty?, s.bytesize == 0]
end

# A leading NUL through a variable and through a method call, so the answer is
# not a constant folded from the literal.
def first_nul(s) = "\0" + s
p first_nul("x").empty?
v = "\0y"
p v.empty?

# valid_encoding? asks the same question of the same bytes: a NUL is a valid
# UTF-8 character, so the scan cannot stop there and call the rest valid.
p "a\0b".valid_encoding?
p "a\0\xff".valid_encoding?
p "\xff".valid_encoding?
p "a\0\xff".b.valid_encoding?
