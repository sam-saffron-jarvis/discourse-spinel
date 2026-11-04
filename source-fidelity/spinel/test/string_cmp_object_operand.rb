# `"abc" <=> obj` for an object that is not a String and has no #to_str.
#
# CRuby's String#<=> does not stop when rb_check_string_type declines: it
# falls back to rb_invcmp, asking the OPERAND to compare itself against the
# string and negating the answer, which is nil when the operand's class has no
# `<=>` of its own or answers nil with one. spinel raised NoMethodError
# naming String#<=>, a method String has. String is the only receiver with
# this rule -- Integer, Float, Symbol, Array and nil all answer nil for the
# same operand, and the lines below check that too.
class WithCmp
  def <=>(o)
    o.is_a?(String) ? (o == "abc" ? 0 : 1) : nil
  end
end
class Bare; end
class Conv
  def to_str = "abd"
end
class Seven
  def <=>(o) = 7      # rb_cmpint normalizes before the negation
end

def id(x) = x

# a statically typed operand
m = WithCmp.new
p("abc" <=> m)
p("abd" <=> m)
p("abc" <=> Bare.new)
p("abc" <=> Conv.new)
p("abc" <=> Seven.new)

# the same through a run-time-typed operand
p("abc" <=> id(m))
p("abd" <=> id(m))
p("abc" <=> id(Bare.new))
p("abc" <=> id(Conv.new))
p("abc" <=> id(Seven.new))

# the operand's own answer of nil stays nil
p(m <=> 1)

# every other receiver answers nil for an operand with a `<=>`
p(1 <=> id(Seven.new))
p(1.5 <=> id(Seven.new))
p(:s <=> id(Seven.new))
p([1] <=> id(Seven.new))
p(nil <=> id(Seven.new))

# the ordered operators keep raising, which is CRuby's answer for them
begin
  p("abc" < Bare.new)
rescue ArgumentError => e
  puts e.message
end
