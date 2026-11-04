# spinel: int64
require "io/buffer"

# get_value/set_value with a literal type symbol lower to the typed accessor.
# The offset and the stored value need not be statically Integer for that:
# a parameter reached by two argument kinds is boxed, and under
# --int-overflow=promote every int local is. Requiring a machine int lost the
# lowering exactly where the loop that wants it lives.

buf = IO::Buffer.new(32)

def read32(b, off)  = b.get_value(:U32, off)
def write32(b, off, v) = b.set_value(:U32, off, v)
def read64(b, off)  = b.get_value(:U64, off)
def write64(b, off, v) = b.set_value(:U64, off, v)

# the boxing: each parameter is reached by an Integer and by something else
read32(buf, "x") rescue p $!.class
write32(buf, 0, "x") rescue p $!.class

write32(buf, 0, 0xCAFEBABE)
p read32(buf, 0)

# a Float in an integer slot truncates, as it does through the generic path
write32(buf, 4, 3.9)
p read32(buf, 4)

# u64 holds what an sp_int cannot: the value stays a Bignum both ways
write64(buf, 8, 18446744073709551615)
p read64(buf, 8)
p read64(buf, 8).class

# the sign of a narrower type still follows the type, not the slot
buf.set_value(:S32, 16, -5)
def readS32(b, off) = b.get_value(:S32, off)
p readS32(buf, 16)

# a bad offset is still refused, through the typed accessor
read32(buf, 100) rescue p $!.class

# and the shape this exists for: an offset computed in a loop
i = 0
while i < 4
  write32(buf, i * 4, i * 1000)
  i += 1
end
i = 0
sum = 0
while i < 4
  sum += read32(buf, i * 4)
  i += 1
end
p sum
