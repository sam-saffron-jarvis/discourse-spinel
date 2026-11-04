# Hash#replace takes the other hash's default along with its entries, as in
# CRuby, through a boxed receiver too: the boxed `replace` kept the
# receiver's own, so `Hash.new(1).replace(b: 2).default` answered 1. A bang
# transform, which the analyzer lowers to a `replace` of the transformed
# copy, still keeps the receiver's default, since that copy is the
# receiver's own entries.
src = {x: 1}
src.default = 9
h = {a: 1}
h.default = 4
box = [h, 0][0]
box.replace(src)
p [box.default, h.default, h[:zz], h]
h2 = {a: 1}
h2.default = 4
box2 = [h2, 0][0]
box2.transform_values! { |v| v + 1 }
p [box2.default, h2]
g = {1 => 2, "s" => 3}
bg = [g, 0][0]
bg.default = 5
bg.replace(src)
p [bg.default, bg[:zz], g]
