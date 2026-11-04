# promote-only: an Integer `**` whose operands are not both constants can
# escape the word at run time, and under --int-overflow=promote it promotes
# to a Bignum -- the `<<` rule. A TYPED operand (a block parameter, an
# array element) used to take the int helper, which raises; the boxed
# path (a local, a method parameter) already promoted. In raise mode the
# same expressions raise RangeError, so the test is filtered out there.
[100].each { |e| p 2**e }
[64, 100].each { |e| v = 2**e; p v }
a = []
[100].each { |e| a << 2**e }
p a.first
[3].each { |b| p b**2 }
[2].each { |b| p b**-2 }
[2**40].each { |b| p b**2 }
p [5, 6, 70].map { |e| 2**e }
p [2, 3].map { |b| b**b }
e = 100
p 2**e
def pw(b, e) = b**e
p pw(2, 100)
p pw(7, 2)
p 2**100
p 2**10
