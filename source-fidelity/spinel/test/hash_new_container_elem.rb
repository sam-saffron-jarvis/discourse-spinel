# A Hash.new placed straight into an array or hash literal has no local of
# its own whose uses could narrow it. Left unknown, `[Hash.new(4), 0]` took
# an Integer element, the Hash.new became a call to an undefined method, and
# the C build failed. It is the widest hash, as a Hash.new used directly as
# a receiver already is.
box = [Hash.new(4), 0][0]
p box.default
p box[:x]
box[:y] = 1
p box
hs = {a: Hash.new(0), b: 1}
hs[:a][:k] += 1
p hs
list = [Hash.new(0), Hash.new(0)]
list[0]["w"] += 2
p list
