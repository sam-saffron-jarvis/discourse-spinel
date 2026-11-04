# Integer#allbits? / #anybits? / #nobits? on a BOXED receiver -- a slot that
# may hold a Bignum (every Integer parameter under --int-overflow=promote,
# a value read out of a poly container in any mode). The runtime helper
# answers by the box's tag: an Integer pair tests in the word, a Bignum on
# either side tests in the Bignum, and a negative receiver is sign-extended
# past the mask as CRuby's is. The face re-entry used to narrow the box to
# sp_int, or raise NoMethodError for the Bignum it had.
def bits(x, m) = [x.allbits?(m), x.anybits?(m), x.nobits?(m)]

vals = [14, -1, 2**100 + 6, -(2**70), 0]
masks = [6, 1, 2**100, 2**100 + 2, 2**64, 0]
vals.each do |v|
  masks.each do |m|
    p [v, m, bits(v, m)]
  end
end

box = [14, 2**100 + 6, "s"]
p box[0].allbits?(6)
p box[1].allbits?(2**100)
p box[1].anybits?(2**64)
p box[1].nobits?(1)
p box[1].respond_to?(:allbits?)
begin
  box[2].anybits?(1)
rescue NoMethodError => e
  puts e.message.sub(/ for .*/, "")
end
