# `h[k] ||= v` is `h[k] || (h[k] = v)`: the READ decides, and on a miss the
# read answers the hash's default. The statement form tested key presence
# instead, so a truthy default took the write where CRuby keeps it, and `&&=`
# refused the write the truthy default calls for. The expression form already
# read the slot; the statement form now does the same.
a = Hash.new(0);     a["c"] ||= 7;    p [a["c"], a.sort]
b = Hash.new(0);     b["c"] &&= 7;    p [b["c"], b.sort]
c = Hash.new;        c["c"] ||= 7;    p [c["c"], c.sort]
d = Hash.new;        d["c"] &&= 7;    p [d["c"], d.sort]
e = Hash.new("d");   e["k"] ||= "v";  p [e["k"], e.sort]
f = Hash.new(5);     f[1] ||= 9;      p [f[1], f.sort]
g = Hash.new(5);     g[1] &&= 9;      p [g[1], g.sort]
h = { "x" => 1 };    h["x"] ||= 9;    h["x"] &&= 3;  p h
i = Hash.new(0);     i[:s] ||= 4;     p [i[:s], i.sort]
# a present falsy value is still overwritten by ||= and kept by &&=
j = { "n" => nil };  j["n"] ||= 2;    p j
k = { "n" => nil };  k["n"] &&= 2;    p k
# `Hash.new(nil)` is `Hash.new`: a miss is nil, not a zero
l = Hash.new(nil);   l["c"] ||= 7;    p [l["c"], l["zz"]]
$m = Hash.new(nil);  $m["c"] ||= 8;   p [$m["c"], $m["zz"]]
# the value of the expression form agrees with the statement form
n = Hash.new(0);     x = (n["c"] ||= 7); p [x, n.sort]
