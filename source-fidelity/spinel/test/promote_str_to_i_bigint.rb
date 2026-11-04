# Under --int-overflow=promote, String#to_i and Integer() read a value past
# the machine word as a Bignum, as CRuby does, where they raised RangeError.
# The default raise mode keeps its RangeError (docs/int-overflow.md).
p "9223372036854775808".to_i
p "-9223372036854775809".to_i
p "-9223372036854775808".to_i
p "123456789012345678901234567890".to_i
p "12_345_678_901_234_567_890abc".to_i
p "ffffffffffffffffffff".to_i(16)
p "42".to_i, "x".to_i, "  -7 ".to_i
p Integer("99999999999999999999")
p Integer("0x1_0000_0000_0000_0000")
p Integer("18446744073709551616", 10)
p Integer("99999999999999999999x", exception: false)
p Integer("99999999999999999999", exception: false)
p Integer("12")
begin
  Integer("99999999999999999999x")
rescue ArgumentError => e
  p e.message
end
x = "9223372036854775807".to_i
p x + 1
p "18446744073709551616".to_i + 1
