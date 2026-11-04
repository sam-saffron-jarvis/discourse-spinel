# Under --int-overflow=promote an int << promotes to a Bignum whenever the
# result escapes the word -- with a RUNTIME count too, not only the folded
# literal pair. The count past the word, the in-word count whose RESULT
# overflows, and the literal count over a runtime receiver all promote; the
# small results stay exact ints; >> and a negative count shift right.
n = ARGV.length + 63
p(1 << n)                # count at the word: 2^63
p(3 << (n - 1))          # in-word count, overflowing result
x = ARGV.length + 3
p(x << 61)               # literal count, runtime receiver
p(x << 1)                # small: stays an exact int
p(1 << (n - 63))         # zero count
p(-1 << n)               # negative receiver promotes too
m = ARGV.length - 5
p(64 << m)               # negative count shifts right
p(0 << n)                # zero receiver stays zero
p((1 << n) >> n)         # the promoted value shifts back down
p((1 << n) + 1)          # ...and carries through arithmetic
p((1 << n) * 2)
v = 1
v <<= n                  # op-assign takes the same promotion
p v
acc = 0
4.times { |k| acc |= (1 << (n - k)) }   # OR-accumulation keeps every bit
p acc
acc &= (1 << n)          # op-assign & against a Bignum keeps its width
p acc
