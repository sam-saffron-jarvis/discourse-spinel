# Array#replace makes the receiver a copy of the source, whatever the source
# holds. A source of ANOTHER element kind left the receiver its old typed
# array, which had no arm that could take one, and the call answered
# NoMethodError (#4339). The receiver widens like concat's does, and the poly
# arm reads the source through the boxed accessors.
a = [1, 2]
a.replace(["x", "y"])
p a

b = [1, 2]
b.replace([3.5])
p b

c = [1, 2]
d = ["x", "y"]
c.replace(d)
p c

# the same-kind forms keep their tuned arms
e = [1, 2]
e.replace([3, 4])
p e
f = ["p", "q"]
f.replace(["r"])
p f
g = [1.5, 2.5]
g.replace([3.5])
p g

# replace answers the receiver, and an empty source empties it
h = [1, 2]
p h.replace([9]).size
i = [1, 2]
i.replace([])
p i

# a boxed receiver, and one whose kind is only known at run time
j = { k: [1, 2, 3] }
j[:k].replace([4, 5])
p j[:k]
k = [[1, 2, 3], 0][0]
k.replace([4, 5])
p k

# replacing with itself is a no-op, not a truncation
m = [1, 2, 3]
m.replace(m)
p m

# a frozen receiver raises before the truncation, and the frozen bit survives
# the widening a cross-kind call needs
n = [1, 2].freeze
r = (n.replace(["x"]) rescue $!.class); p r
o = [1, 2].freeze
r2 = (o.replace([3, 4]) rescue $!.class); p r2
q = [1, 2].freeze
r3 = (q.push("x") rescue $!.class); p r3
s = ["a"].freeze
r4 = (s.replace(["b"]) rescue $!.class); p r4
t = [1.5].freeze
r5 = (t.replace([2.5]) rescue $!.class); p r5

# a String and a Hash keep their own replace
u = +"abc"
u.replace("xyz")
p u
v = { a: 1 }
v.replace({ b: 2 })
p v
