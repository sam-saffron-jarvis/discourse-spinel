# A double-splat of a same-variant hash into a hash literal merges through
# sp_<kind>Hash_update. Only the symbol-keyed and poly-keyed variants defined
# it, so a `**` spread of an Integer-keyed hash, or of a String-keyed hash
# with mixed values, compiled to a call the runtime did not have and the
# program failed to link.

# 1. Integer keys, Integer values.
ii = { 1 => 2 }
p({ **ii, 3 => 4 })                        #=> {1 => 2, 3 => 4}

# 2. Integer keys, String values.
is = { 1 => "a" }
p({ **is, 2 => "b" })                      #=> {1 => "a", 2 => "b"}

# 3. String keys, mixed values.
sp = { "a" => 1, "b" => "x" }
p({ **sp, "c" => 2.5 })                    #=> {"a" => 1, "b" => "x", "c" => 2.5}

# 4. A later explicit key overrides the spread one (last wins).
p({ **ii, 1 => 9 })                        #=> {1 => 9}
p({ **sp, "a" => "over" })                 #=> {"a" => "over", "b" => "x"}

# 5. Spreading an empty literal: `{}` with no other evidence is typed as the
#    String-keyed poly variant.
e = {}
p({ **e })                                 #=> {}
p({ **e, "k" => 1 })                       #=> {"k" => 1}

# 6. Two spreads of the same variant.
jj = { 5 => 6 }
p({ **ii, **jj })                          #=> {1 => 2, 5 => 6}
