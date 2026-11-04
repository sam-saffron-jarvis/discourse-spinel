# `key?` on a Hash read out of a nested Hash literal, with the key arriving
# boxed (a method parameter fed several kinds): only the general hash had an
# arm, so a Symbol-, String- or Integer-keyed hash answered false for every
# key, and an options merge ignored every option the caller set (#5074).

A = { x: { k: nil, j: true } }

def has(options, group, key)
  g = options[group]
  g.key?(key)
end

[:k, :j, :z].each { |k| p has(A, :x, k) }

H = { s: { "a" => 1, "b" => "two" }, i: { 1 => 2 }, y: { k: 1 } }
def probe(h, g, key) = [h[g].key?(key), h[g].include?(key), h[g].member?(key), h[g].has_key?(key)]
p probe(H, :s, "a")
p probe(H, :s, "z")
p probe(H, :s, :a)
p probe(H, :i, 1)
p probe(H, :i, 2)
p probe(H, :y, :k)
p probe(H, :y, "k")
