# A global or a constant assigned `Hash.new(default)` takes the hash variant its
# own writes imply, carrying the default, exactly as a local does. Before, the
# empty-producer rule admitted only the argument-less `Hash.new`, so such a
# global stayed on the poly slot where every call that read it typed as nil
# and its value was discarded, and the constant form did not build at all.

$counts = Hash.new(0)
$counts["b"] = 1
p $counts["b"]
p $counts["zz"]          # the default, not nil
p $counts.size
p $counts.sort
p $counts.to_a
p $counts.min_by { |k, v| v }
p $counts.max

# read-modify-write forms, which carry the key in a different place
$tally = Hash.new(0)
$tally["a"] += 1
$tally["a"] += 1
$tally["b"] += 2
p $tally["a"]
p $tally["q"]
p $tally.sort

# the same through a method, where the write is not at the top level
$seen = Hash.new(0)
def bump(k)
  $seen[k] += 1
end
bump("x"); bump("x"); bump("y")
p $seen["x"]
p $seen["none"]
p $seen.sort

# symbol keys
$sym = Hash.new(0)
$sym[:a] += 1
$sym[:b] ||= 5
p [$sym[:a], $sym[:b], $sym[:zz]]

# a default of another kind than the values: the value type widens to poly and
# the default is carried boxed, so a miss answers it
$mixed = Hash.new("none")
$mixed["b"] = 1
p $mixed["b"]
p $mixed["zz"]
p $mixed.sort

# a default of the values' own kind
$names = Hash.new("anon")
$names["b"] = "one"
p [$names["b"], $names["zz"]]

# never written: the default alone decides
$lonely = Hash.new("dflt")
p [$lonely["zz"], $lonely.size]

# the constant form
COUNTS = Hash.new(0)
COUNTS["x"] += 1
COUNTS["x"] += 1
COUNTS["y"] = 5
p [COUNTS["x"], COUNTS["y"], COUNTS["zz"]]
p COUNTS.sort

# the shapes that already worked keep their answers
$bare = Hash.new
$bare["b"] = 1
p [$bare["b"], $bare["zz"]]
$lit = {}
$lit["b"] = 1
p [$lit["b"], $lit["zz"]]
$blk = Hash.new { |h, k| h[k] = k.length }
$blk["four"] += 1
p [$blk["four"], $blk["seven"]]
