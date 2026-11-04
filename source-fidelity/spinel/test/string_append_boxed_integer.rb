# `String#<<` with an Integer appends the CODEPOINT, and a boxed Integer is the
# same Integer.
#
# The rule was written twice. The value-position emitter and the
# statement-position chain emitter each had the typed half -- `s << 112` with
# 112 known to be an Integer appends "p" -- and each stringified a BOXED one,
# so the same statement appended "112" once the operand's type had widened.
# Nothing raised; the program ran to completion with the wrong string (#4425).
#
# What makes it reach further than it looks: ONE poly-typed call site widens the
# operand for the whole method, so a caller that passes a literal String pays
# for a caller that passes a hash read. Deleting the second `puts` below made
# the first one correct, which is the shape the reporter noticed.
#
# Both emitters now call one helper, because a rule in two places is a rule that
# drifts, and this one already had.
def bytes_of(s)
  out = String.new
  i = 0
  while i < s.bytesize
    out << s.getbyte(i)
    i += 1
  end
  out
end

h = { "a" => "pq", "n" => 63 }

# the literal caller and the poly caller agree
puts bytes_of("pq")
puts bytes_of(h["a"])

# the value position, where the append's result is used
buf = String.new
r = (buf << h["n"])
puts r
puts buf

# a typed Integer still appends its codepoint, and a String still concatenates
t = String.new
t << 104
t << "i"
puts t

# concat takes an Integer the same way
cc = String.new
cc.concat(122)
puts cc

# a boxed String on the right is still a concatenation, not a codepoint
mixed = String.new
mixed << h["a"]
mixed << 33
puts mixed
