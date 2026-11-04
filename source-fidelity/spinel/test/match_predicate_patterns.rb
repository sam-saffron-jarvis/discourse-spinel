# `expr in pattern` is the one-arm `case expr; in pattern then true; else
# false; end`. The predicate had its own condition emitter, which refused a
# qualified array or hash pattern (`v in Pt[1, _]`) and bound none of the
# pattern's names, where CRuby binds them.
Pt = Struct.new(:x, :y)
v = Pt.new(1, 2)
p((v in Pt[1, _]))
p((v in Pt[2, _]))
p((v in Pt(x: 1)))
w = {name: "a", age: 3}
p((w in {name: String}))
p((w in {name: Integer}))
p((5 in Integer))
p(("s" in Integer | String))
if v in Pt[a, b]
  p [a, b]
end
if w in {age: Integer => age}
  p age
end
