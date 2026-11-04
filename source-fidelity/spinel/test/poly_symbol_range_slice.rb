# A Symbol indexed with a Range answers its own name sliced, because
# `Symbol#[]` is `String#[]` on `#to_s`. The Range arms of the boxed `[]`
# took only a String or an array kind, so a symbol receiver fell past all of
# them to the trailing nil -- the same lost value #4769 fixed for the
# two-argument `:symbol[0, 3]`.
#
# The String arm beside it had its own hole: a BEGINLESS Range carries
# INTPTR_MIN as its first, which is a sentinel and not an index, and the
# string helper read it as an ordinary negative and counted back from the
# end. `["symbol", 1][0][..2]` was nil where CRuby says "sym". The array
# reader already translated the sentinel; now the string and symbol arms do.
def at(x, r) = x[r]

s = [:symbol, nil][0]
p at(s, 0..2)
p at(s, 1..)
p at(s, 0...3)
p at(s, -3..)
p at(s, ..2)
p at(s, ...2)
p at(s, 9..10)
p at(s, 6..7)

t = ["symbol", 1][0]
p at(t, 0..2)
p at(t, 1..)
p at(t, ..2)
p at(t, ...2)
p at(t, -3..)
p at(t, 9..10)
p at(t, 6..7)
