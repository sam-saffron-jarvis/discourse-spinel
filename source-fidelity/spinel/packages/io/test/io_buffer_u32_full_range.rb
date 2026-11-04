# A 32-bit IO::Buffer type takes any value whose magnitude fits the field,
# however the value is held: on a 32-bit build every value past 2**31-1 is a
# heap Bignum, 0xCAFEBABE included, and iob_int_operand refused every Bignum
# for a 32-bit type on the grounds that one is out of range by definition
# (#4647). Runs on the -m32 lane too, which is the build it is for.
require "io/buffer"
buf = IO::Buffer.new(8)
buf.set_value(:U32, 0, 0xCAFEBABE)
p buf.get_value(:U32, 0)
buf.set_value(:S32, 0, -2147483648)
p buf.get_value(:S32, 0)
buf.set_value(:U32, 0, 4294967295)
p buf.get_value(:U32, 0)
begin
  buf.set_value(:U32, 0, 4294967296)
rescue RangeError => e
  puts e.class
end
begin
  buf.set_value(:S32, 0, 2147483648)
rescue RangeError => e
  puts e.class
end
begin
  buf.set_value(:S32, 0, -2147483649)
rescue RangeError => e
  puts e.class
end
