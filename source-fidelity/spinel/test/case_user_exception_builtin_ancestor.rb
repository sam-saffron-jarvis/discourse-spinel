# A user exception object, typed as its own class, matches a `when` or `in`
# arm naming a builtin ancestor: `when StandardError`, `when Exception`,
# `in StandardError`; a poly value does the same, and answers `is_a?`,
# `kind_of?` and `===`. On c24731a1 the typed arm folded to false at compile
# time, since the compiler's class table ends at the program's classes and
# cannot see the builtin above them, and the poly walk skipped a user class,
# so every line marked "builtin" below took its else arm or answered false,
# and the two marked "misses" should. Arms naming the
# object's own class, a user ancestor or Object were right and still are.
class MyErr < StandardError; end
class Sub < MyErr; end
class Other < RuntimeError; end

e = MyErr.new("x")
p [:when_standard_error, (case e when StandardError then :yes else :no end)]     # builtin
p [:when_exception, (case e when Exception then :yes else :no end)]              # builtin
p [:in_standard_error, (case e; in StandardError then :yes; else :no; end)]      # builtin
p [:when_runtime_error, (case e when RuntimeError then :yes else :no end)]       # builtin, misses
p [:when_own_class, (case e when MyErr then :yes else :no end)]
p [:when_object, (case e when Object then :yes else :no end)]

s = Sub.new("y")
p [:sub_when_user_ancestor, (case s when MyErr then :yes else :no end)]
p [:sub_when_standard_error, (case s when StandardError then :yes else :no end)] # builtin
p [:sub_in_exception, (case s; in Exception then :yes; else :no; end)]           # builtin

o = Other.new("z")
p [:other_when_runtime_error, (case o when RuntimeError then :yes else :no end)] # builtin
p [:other_when_arg_error, (case o when ArgumentError then :yes else :no end)]    # builtin, misses

# the statement form, with the builtin arm after a missing one   # builtin
case e
when RuntimeError then p [:stmt, :runtime]
when StandardError then p [:stmt, :standard]
else p [:stmt, :none]
end

def kind(x) = case x when ArgumentError then :arg when StandardError then :std when Exception then :exc else :other end
p [:def, kind(MyErr.new), kind(Other.new)]                                  # builtin, poly subject

# the same runtime walk answers is_a?, kind_of? and === on a poly value
u = [1, MyErr.new("w")][1]
p [:poly_is_a, u.is_a?(StandardError), u.kind_of?(Exception), u.is_a?(RuntimeError)]  # builtin, poly subject
p [:poly_eqq, StandardError === u, Exception === u, ArgumentError === u]               # builtin, poly subject
