# A branch expression whose result is a Bignum, with an arm that is not one.
# The arm is a value and the result slot is an sp_Bigint *, so the arm was
# assigned into it raw -- an integer reinterpreted as a pointer, and the
# first read of it segfaulted. The C compiler does say so ("pointer/integer
# type mismatch in conditional expression"), but the generated TU is built
# with -Wall off, so it was a warning and the build completed.
#
# Only an arm sitting in a C conditional (or a case's result temp) beside a
# bigint sibling reached it: the implicit-tail form returns from each branch
# separately and takes the return path's own int-to-bigint wrap, so
# `def f(x); x == 1 ? BIG : SMALL; end` was always right while the same body
# behind `return` was not. The case form did not even compile.
def tern(x)
  return x == 1 ? 9223372036854775808 : 9223372036854775807
end

def iff(x)
  return (if x == 1 then 9223372036854775808 else 9223372036854775807 end)
end

def unl(x)
  return (unless x == 1 then 9223372036854775807 else 9223372036854775808 end)
end

def cse(x)
  return (case x when 1 then 9223372036854775808 else 9223372036854775807 end)
end

def tern_var(x, n)
  return x == 1 ? 9223372036854775808 : n
end

def nested(x)
  return x == 1 ? 9223372036854775808 : (x == 2 ? 9223372036854775807 : 3)
end

# the implicit tail, which was already right and must stay so
def tail(x)
  x == 1 ? 9223372036854775808 : 9223372036854775807
end

[1, 2].each { |v| p tern(v) }
[1, 2].each { |v| p iff(v) }
[1, 2].each { |v| p unl(v) }
[1, 2].each { |v| p cse(v) }
[1, 2].each { |v| p tern_var(v, 5) }
[1, 2, 3].each { |v| p nested(v) }
[1, 2].each { |v| p tail(v) }
