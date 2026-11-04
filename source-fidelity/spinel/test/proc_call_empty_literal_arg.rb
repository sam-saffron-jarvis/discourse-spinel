# An empty `[]` / `{}` literal passed to a lambda or proc. Two halves had to
# agree and neither did (#4295).
#
# A proc literal's required params default to int when nothing pins them, and
# the call-site typing skipped an argument whose type is UNKNOWN -- which an
# empty literal always is. So the parameter stayed an int while the argument
# was still BUILT as a container, and an sp_IntArray * went into an sp_int
# slot: the program did not compile.
#
# The argument emitter then asks the node's own type to decide whether the
# value is storable. An empty hash literal had none, so it declared an sp_int
# temp and boxed nil onto the side channel while the literal built a hash.

f = ->(a) { a }
p f.call([])
p f.call({})

g = proc { |a| a }
p g.call([])
p g.call({})

# both at once, and mixed with a typed argument
h = ->(a, b) { [a, b] }
p h.call([], {})
i = ->(a, b) { [a, b] }
p i.call([], 3)

# a non-empty literal and a scalar still take their own types
j = ->(a) { a }
p j.call([1])
p j.call({ a: 1 }.size)
k = ->(a) { a * 2 }
p k.call(3)
p k.call("ab")

# the parameter really is the container, not a number
l = ->(acc) { acc.push(9); acc }
p l.call([])
