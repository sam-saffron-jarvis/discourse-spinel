# `sum` folds from an Integer 0, so a value with no `+` raises TypeError.
# The folds used to decline these shapes and the generic dispatch answered
# NoMethodError, or emitted a call to an sp_StrArray_sum that does not exist
# (#4327).
r = ([1, 2].sum { |i| true } rescue $!.class); p r
r = ([1, 2].sum { |i| "s" } rescue $!.class); p r
r = ([1, 2].sum { |i| :s } rescue $!.class); p r
r = ([1, 2].sum { |i| nil } rescue $!.class); p r
r = (["a", "b"].sum rescue $!.class); p r
r = (["a"].sum(0) rescue $!.class); p r

# an empty receiver never runs the addition, so it answers the seed
e = ["a"]
e.pop
r = (e.sum rescue $!.class); p r
p [].sum

# and the shapes that do add still add
p(["a", "b"].sum(""))
p([1, 2].sum { |i| i * 2 })
p([1.5, 2.5].sum)
p([1, 2].sum(0.5))
