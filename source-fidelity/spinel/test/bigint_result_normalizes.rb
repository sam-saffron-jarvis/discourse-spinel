# spinel: int64
# Ruby has ONE Integer: a bigint operation whose result fits the inline
# representation answers the inline one, as CRuby does. Boxed as a Bignum
# whatever its size, such a value read right when printed or compared and was
# refused by every consumer that decides on the tag -- IO::Buffer's u32 lane
# called `big & 0xffff_ffff` "bignum too big to convert into 'unsigned int'".
B = 18446744073709551615
vals = {
  "and"   => B & 0xffff_ffff,
  "or"    => (B & 0xffff_ffff) | 0,
  "xor"   => B ^ 0xffff_ffff_0000_0000,
  "div"   => B / (2**32),
  "mod"   => B % 1000,
  "sub"   => B - (B - 7),
  "shr"   => B >> 40,
  "mul0"  => B * 0,
  "add"   => (B - B) + 12,
  "pow0"  => B ** 0,
}
buf = IO::Buffer.new(64)
vals.each do |k, v|
  buf.set_value(:u32, 0, v & 0xffff_ffff)
  puts "#{k} #{v} #{buf.get_value(:u32, 0)}"
end
# ...and a result that genuinely needs a Bignum still is one
p B * B
p (B * B) > B
p B + 1
p((2**63) - 1)          # the largest inline value
p(-(2**63))             # INTPTR_MIN: the inline slot spells it nil, so it stays a Bignum
p((-(2**63)) - 1)
p B.class
p (B & 0xff).class
