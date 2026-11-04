# The poly-dispatch collision gap (see poly_numeric_collision.rb) had a
# second, more severe instance for divmod/remainder/fdiv: the "poly
# arithmetic" arm shared by +/-/*//,%,**,quo,fdiv,div,divmod,modulo,
# remainder for a run-time-typed receiver (codegen_call.c's own emit_call)
# had no `user_defines_or_reads` guard at all for the named divisions, so a
# poly receiver whose actual class defined one of these names NEVER reached
# that method -- it always ran the numeric runtime helper unconditionally,
# and for a genuinely non-numeric receiver (a real user object) that helper
# either mis-coerced it (divmod: "no implicit conversion of Widget into
# Integer", the object's own divmod never called) or raised a NoMethodError
# naming the wrong thing. Fixed by declining that arm when the name is
# contested, falling through to the existing poly-dispatch collision switch
# (which already knows how to serve the user class's own case, and now
# has a default arm for divmod/remainder/fdiv answering the numeric case
# too, mirroring poly_numeric_collision.rb's own mechanism).

class Widget
  def divmod(x) = "widget-divmod"
  def remainder(x) = "widget-remainder"
  def fdiv(x) = "widget-fdiv"
end

class WidgetDiffArity
  def divmod(x, y) = "diff-divmod"
  def remainder(x, y) = "diff-remainder"
  def fdiv(x, y) = "diff-fdiv"
end

def pick(v) = v

w = Widget.new
d = WidgetDiffArity.new

# the colliding class still answers for its own instances
p pick(w).divmod(1)
p pick(w).remainder(1)
p pick(w).fdiv(1)

# an Integer receiver still reaches the numeric implementation (same-arity
# collision)
p pick(7).divmod(2)
p pick(7).remainder(2)
p pick(7).fdiv(2)
p pick(-7).divmod(2)
p pick(-7).remainder(2)

# a Bignum receiver too
p pick(2 ** 70).divmod(3)
p pick(2 ** 70).remainder(3)
p pick(2 ** 70).fdiv(3)

# different-arity collision: the colliding class's own method does not
# match this call site's arity, so the numeric implementation still has
# to answer
p pick(d).divmod(1, 2)
p pick(7).divmod(2)
p pick(d).remainder(1, 2)
p pick(7).remainder(2)
p pick(d).fdiv(1, 2)
p pick(7).fdiv(2)

# String/Symbol/Array/Hash/nil receivers of a contested name keep their
# own (raising) answer
[ "hi", :sym, [1, 2], { a: 1 }, nil ].each do |v|
  begin
    p pick(v).remainder(2)
  rescue NoMethodError
    p :nomethod
  end
end
