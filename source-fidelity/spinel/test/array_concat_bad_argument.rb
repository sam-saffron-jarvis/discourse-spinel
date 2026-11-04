# An Array method that takes "something Array-like" used to answer for the
# wrong reason when the argument could not be one. Reachability is decided by
# whether an arm can serve the call, so a Hash, String, Range or Integer
# argument found no arm and fell to the poly dispatch's NoMethodError -- and
# for concat it was worse than that: the container-usage rule read the
# argument as element evidence, widened the receiver's slot to match it, and
# the program stopped compiling.
#
# These are TypeError in CRuby, and the class is known at compile time, so the
# arm that already named nil and false names the rest.
a = [1, 2]
r = (a.concat({ b: 2 }) rescue $!.message); p r
b = [1, 2]
r = (b.concat("xy") rescue $!.message); p r
c = [1, 2]
r = (c.concat(1..3) rescue $!.message); p r
d = [1, 2]
r = (d.concat(5) rescue $!.message); p r
e = [1, 2]
r = (e.concat(nil) rescue $!.message); p r
f = [1, 2]
r = (f.replace({ b: 2 }) rescue $!.message); p r
g = [1, 2]
r = (g.replace(5) rescue $!.message); p r

# the siblings on the same arm
h = [1, 2]
r = (h.union("x") rescue $!.class); p r
i = [1, 2]
r = (i.product(5) rescue $!.class); p r
j = [1, 2]
r = (j.difference({ b: 1 }) rescue $!.class); p r

# ...and every shape that CAN be one still works
k = [1, 2]
k.concat([3])
p k
l = [1, 2]
l.concat(["x"])
p l
m = [1, 2, 3]
p m.intersection([2, 3])
n = [1, 2]
n.replace([9])
p n
# a String receiver keeps String#concat
s = +"ab"
s.concat("cd")
p s
# an argument whose class is only known at run time is not pre-judged
x = [[3, 4], 0][0]
o = [1, 2]
o.concat(x)
p o
