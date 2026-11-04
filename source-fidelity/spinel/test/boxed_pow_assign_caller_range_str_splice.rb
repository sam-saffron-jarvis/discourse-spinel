# Three emitter arms that were keyed on an exact Integer type and refused a
# boxed value, so the program did not build in either mode once a boxed
# Integer reached them (under --int-overflow=promote every Integer local and
# method answer is boxed, which is how the promote suite met all three):
# `**=` on a local, `caller(lo..hi)`, and `str[start, len] = v`.

# `**=` (the binary `**` already took a boxed base)
x = [5, nil][0]
x **= 3
p x
f = 5
f **= 3
p f

# caller(lo..hi) with boxed endpoints, evaluated once each, left first
log = []
def lo(log)
  log << :lo
  0
end
def hi(log)
  log << :hi
  3
end
frames = caller(lo(log)..hi(log))
p log
p frames.is_a?(Array)
lo2 = [0, nil][0]
p caller(lo2..3).is_a?(Array)
p caller(lo2...3).is_a?(Array)

# str[start, len] = v with a boxed start
s = +"hello world"
i = [6, nil][0]
s[i, 5] = "there"
p s
j = 0
s[j, 5] = "HELLO"
p s
s[[-5, nil][0], 5] = "WORLD"
p s
