# A receiver-less call is a call on self, and spinel resolves one by looking for
# a Ruby method of self's class. The universal surface is not a Ruby method, so
# every one of those was a NameError -- in EVERY class, not just a reopened
# Object:
#
#   class Foo
#     def label = "x: " + to_s     # undefined local variable or method 'to_s'
#   end
#
# Two passes already gave an implicit self the receiver it means -- one for a
# native class's own surface, one for five Object predicates. The second's list
# was deliberately short and that is what brought it back (#4387), so the names
# come from the universal answer table now (AN_POLY_RAW), which the inference
# already keeps as the single statement of what a receiver answers.
#
# A name the table carries for some OTHER runtime type -- to_i on a plain object
# -- still has to read as CRuby's bare-identifier NameError rather than as a
# method-call NoMethodError, so the redirected node keeps its vcall flag.
class Foo
  def initialize; @n = 7; end
  def label = "x: " + to_s.class.to_s
  def ins = inspect.class.to_s
  def h = hash.is_a?(Integer)
  def oid = object_id.is_a?(Integer)
  def frz = frozen?
  def nl = nil?
  def own = helper + 1
  def helper = 41
end

f = Foo.new
p f.label
p f.ins
p f.h
p f.oid
p [f.frz, f.nl]
p f.own

# a class's own method still binds ahead of the universal one
class Bar
  def to_s = "BAR-OWN"
  def m = to_s
end
p Bar.new.m

# a reopened Object reaches it too, which is how a library adds a method to
# every object (CRuby's json defines Object#to_json as to_s.to_json)
class Object
  def described = "<" + self.to_s.class.to_s + ">"
end
p 1.described
p "s".described
p Foo.new.described

# The names AN_POLY_RAW cannot carry, because their answer is not a raw C
# scalar: each is checked against the explicit `self.` form beside it, so a name
# that stops being answered fails here rather than going quiet.
class Surface
  def initialize; @n = 5; end
  def probe = [itself.equal?(self.itself), dup.class == self.dup.class,
               clone.class == self.clone.class,
               instance_variables == self.instance_variables,
               instance_variable_get(:@n) == self.instance_variable_get(:@n)]
end
p Surface.new.probe

# The bare Kernel surface is NOT receiver-transparent, so the redirect must not
# reach it: `raise` rewritten to `self.raise` is a NoMethodError. This is the
# shape that caught a list-free version of the pass.
class Abstract
  def area = raise("abstract")
end
begin
  Abstract.new.area
rescue RuntimeError => e
  p ["raise still raises", e.message]
end

# a name nothing answers keeps CRuby's wording, and its class. `to_i` is in the
# universal table -- a poly receiver holding a String answers it -- but a plain
# object does not, so the redirect must not turn its diagnosis into a
# method-call NoMethodError.
class Typo
  def bare = nosuchname
  def wrong_kind = to_i
end
begin
  Typo.new.bare
rescue NameError => e
  p [e.class.to_s, e.message]
end
begin
  Typo.new.wrong_kind
rescue NameError => e
  p [e.class.to_s, e.message]
end
