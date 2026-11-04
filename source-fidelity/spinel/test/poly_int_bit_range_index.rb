# Integer#[range] is the bit field the range names, and a beginless range is
# CRuby's ArgumentError -- the field below bit 0 has no end. The typed arms
# have answered that all along; a BOXED receiver matched no arm in the poly
# index dispatch and left by its trailing hash read, so `b[..3]` answered 1
# instead of raising and `b[0..3]` answered a number that was not the field.
b = [255, nil][0]
begin
  p b[..3]
rescue ArgumentError => e
  puts "beginless: #{e.message}"
end
p b[0..3]
p b[4..]
p b[0...4]
p b[2..5]
p b[5..2]
p b[100..103]

# through a method whose return nothing types, which is how
# --int-overflow=promote reaches the same arm
def thru(v); v; end
begin
  p thru(255)[..3]
rescue ArgumentError => e
  puts "through a method: #{e.message}"
end
p thru(255)[0..3]

# a negative receiver reads its two's-complement bits
n = [-1, nil][0]
p n[0..3]

# a Bignum receiver answers the same way
big = [2**70 + 0b1011, nil][0]
p big[0..3]
p big[70..]

# the single-bit form is unaffected (the two-argument form is #4741's arm,
# in a different helper)
p b[3]
