# SourceFileNode -- the `__FILE__` keyword.
#
# In the entry script `__FILE__` is the path spinel was given, as CRuby's
# is for the script it runs; a required file answers its own absolute
# path (test/source_file_required.rb).
#
# This test exercises __FILE__ end-to-end: it must (a) emit the path,
# (b) flow as `string` through type inference (so dispatch picks the
# string-method arms), (c) interoperate with literals (concat / compare
# / interpolate), and (d) round-trip through a typed-String parameter
# at a method call site.

# Basic emission.
puts __FILE__

# String#length returns an Integer -> dispatch hit the string arm.
puts __FILE__.length > 0

# Concat with literal -> __FILE__ is a `string`, not poly/object.
puts "[" + __FILE__ + "]"

# Interpolation works (path appears verbatim).
puts "got: #{__FILE__}"

# Two reads compare equal -- same toplevel path resolves identically.
puts __FILE__ == __FILE__

# String predicates dispatch via the string arm.
puts __FILE__.end_with?(".rb")
puts __FILE__.include?("source_file")

# Round-trip through a typed-String parameter at a method call site.
def show(s)
  puts "param: " + s
end
show(__FILE__)
