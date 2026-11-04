# An unresolved call (a method defined nowhere) emits the recognizable raise
# token, an sp_RbVal; every ordinary argument site coerces it to the slot's C
# type so the raise survives and the C compiles. A Struct/Data constructor's
# member arguments passed it through raw, and the build stopped at a line
# past the end of the file naming neither the method nor the call (#4216).
# The members coerce now; a dead call site (the empty receiver) compiles and
# never runs, matching CRuby.
Span = Struct.new(:taken, :from, :to)

found = []
p Span.new("a", 0, 1)
p found.map { |one| Span.new(one.text, one.start, one.finish) }

Pt = Data.define(:x, :label)
rows = []
p Pt.new(x: 1, label: "a")
p rows.map { |r| Pt.new(x: r.left, label: r.name) }

# A live unresolved call still raises, with the method named.
class Bare; end

begin
  b = [Bare.new, "x"][0]
  Span.new(b.text, 0, 1)
rescue NoMethodError => e
  puts e.message.include?("text") ? "NoMethodError names it" : e.message
end
