# Float-array search family: index / rindex / find_index / delete, value and
# block forms, mirroring the Int/Str-array support.
a = [1.5, 2.5, 3.5, 2.5]
p a.index(2.5)
p a.rindex(2.5)
p a.find_index(3.5)
p a.index(9.9)
p a.rindex(9.9)

# an Integer needle compares numerically (exact only within 2**53), as
# CRuby's == does for every value a double can hold exactly
b = [1.0, 2.0, 1.0]
p b.index(2)
p b.rindex(1)

# a needle of a kind the array can never hold: nil, both operands evaluated
$probes = 0
def probe = ($probes += 1; "s")
p a.index(probe)
p a.rindex(:sym)
p [$probes, a.length]

# a boxed needle out of a poly container: a Float or Integer compares, any
# other kind misses -- never a to-f coercion, never a false hit
box = ["x", nil, 2.5]
w = [0.0, 1.5, 2.5]
p w.index(box[0])
p w.rindex(box[1])
p w.index(box[2])
p w.delete(box[0])
p w
p w.delete(box[2])
p w
box2 = [2.5, 3]
w2 = [2.5, 3.0, 2.5]
p w2.rindex(box2[0])
p w2.index(box2[1])
p w2.delete(box2[1])
p w2

# block forms scan elements (rindex from the end)
p a.index { |x| x > 2 }
p a.rindex { |x| x < 3 }
p a.find_index { |x| x == 3.5 }
p a.index { |x| x > 99 }

# the found index is an ordinary Integer
p a.index(2.5) + 10

# delete: every occurrence goes, the ELEMENT answers; nil (or the block) on a miss
p b.delete(1)
p b
p a.delete(9.9)
p a.delete(9.9) { "gone" }
p a.delete(2.5) { "gone" }
p a

# delete answers the element it removed, not the needle: -0.0 shows it
z = [-0.0, 1.5]
r = z.delete(0.0)
p r
p 1.0 / r
p z

# the Float::NAN constant finds itself, as include? already does
n = [Float::NAN, 7.5]
p n.index(Float::NAN)
p n.rindex(Float::NAN)
p n.delete(Float::NAN)
p n

# a needle kind == can never match compiles even on a live path (this once
# broke the C build), and answers nil without mutating
def rq(flag, arr) = flag ? arr.delete(Rational(1, 1)) : 0
p rq(false, [1.5])
p rq(true, [1.5, 2.5])

# a float array carried through a poly container deletes in place
h = { k: [1.5, 2.5] }
p h[:k].delete(2.5)
p h[:k]

# genuinely empty and frozen receivers
e = [1.5]
e.pop
p e.index(1.0)
p e.delete(1.0)
f = [4.5].freeze
begin
  f.delete(4.5)
rescue => err
  p err.class
end
