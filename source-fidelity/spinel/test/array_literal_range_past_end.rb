# Array#[] and #slice with a literal Range whose start is outside
# [-length, length] answer nil, as the variable-Range path already did (#4524);
# the literal path went through the runtime slice, which answered [] and
# never nil. `&.` on a typed array receiver guards NULL now as well.
a = [1, 2, 3]
rng = (4..)
x = a[4..]
p x.nil?
y = a[rng]
p y.nil?
p a[4..6].nil?
p a.slice(4..).nil?
p a[-9..].nil?
p(a[4..] || :fallback)
p a[3..]
p a[1..]
p a[-3..]
p a[-4..].nil?
p [][1..].nil?
p [][0..]
p a[4...6].nil?
p ["x", "y"][5..].nil?
p [1.5][2..].nil?
p a[4..]&.size
p a[rng]&.size
x = a[rng]
p x&.size
p x.size if x
