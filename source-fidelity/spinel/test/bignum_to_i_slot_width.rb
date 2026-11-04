# A Bignum reaching an sp_int slot must answer its own value or refuse it --
# never a different number. The width test was the constant 63, so under
# -m32, where sp_int is 32 bits, a value of 33..63 bits passed it and the
# cast then cut it silently.
#
# Whether a given value is answered or refused depends on the target width
# AND on the overflow mode, so neither can be the assertion here. What holds
# everywhere is the invariant the bug broke: the answer is the value or a
# refusal, and never some other number. Values that fit any width are
# checked exactly, to keep a positive claim in the test.
def never_wrong(expected)
  v = yield
  v == expected ? "ok" : "WRONG: #{v}"
rescue RangeError
  "ok"                      # refusing is correct when the slot cannot hold it
end

def exact(expected)
  v = yield
  v == expected ? "exact" : "WRONG: #{v}"
end

# fits every width and mode: always the value itself, never a refusal
[12345, -12345, 2**20].each do |n|
  b = [n, nil][0]
  puts exact(n) { b.to_i }
  puts exact(n) { Integer(b) }
end
puts exact(3) { Rational(12, 4).to_i }
puts exact(5) { [Rational(5, 2), nil][0].numerator }

# the straddling band and beyond, through the two slot conversions the width
# test governs. 1099511627776 and 4611686018427387904 fit a 64-bit sp_int and cannot fit a 32-bit
# one; 2**70 fits neither, and promote answers it while raise refuses it.
# Every one of them must come back whole or not at all.
[1099511627776, 4611686018427387904, -(1099511627776), -(4611686018427387904), 2**70, -(2**70)].each do |n|
  b = [n, nil][0]
  puts never_wrong(n) { b.to_i }
  puts never_wrong(n) { Integer(b) }
end
