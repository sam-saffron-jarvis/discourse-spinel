# The multi-statement arms of an `if`/`unless`/`elsif` used as a value go
# through a result TEMP, not through the flat C conditional: the leading
# statements are hoisted and the arm's last expression is assigned into a
# `_tN` declared at the whole expression's type. That assignment coerced only
# a poly result, so a BIGINT one took a plain Integer arm raw -- an integer
# assigned into an sp_Bigint * slot, which the C compiler refuses outright:
#
#   error: incompatible integer to pointer conversion assigning to 'sp_Bigint *'
#
# #4794 fixed the arms that go through emit_ternary_arm (the flat ternary,
# the single-statement if, and the case result temp). These are the paths
# that do not: a single-statement arm was always fine, and only adding a
# second statement to an arm reached this.
def two_stmt(x)
  return (if x == 1
    a = 1
    9223372036854775808
  else
    b = 2
    9223372036854775807
  end)
end

def with_elsif(x)
  return (if x == 1
    a = 1
    9223372036854775808
  elsif x == 2
    b = 2
    9223372036854775807
  else
    c = 3
    5
  end)
end

def unless_form(x)
  return (unless x == 1
    d = 1
    9223372036854775807
  else
    e = 2
    9223372036854775808
  end)
end

# a folded predicate still has both arms emitted, and the live one is a
# multi-statement arm here
def folded
  return (if false
    y = 2
    9223372036854775807
  else
    z = 3
    9223372036854775808
  end)
end

[1, 2].each { |v| p two_stmt(v) }
[1, 2, 3].each { |v| p with_elsif(v) }
[1, 2].each { |v| p unless_form(v) }
p folded
