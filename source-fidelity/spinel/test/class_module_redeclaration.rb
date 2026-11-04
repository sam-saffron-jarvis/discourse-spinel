# Two shapes CRuby refuses to LOAD built here with nothing said, and each
# answered whatever its FIRST declaration was written with -- the later one was
# dropped, bodies and all (#4309). Both are compile errors now, so what this
# file checks is the shapes next door that are still legal.
#
# A bare reopen with no `<` is how a class is normally added to.
class Base
  def kind = "base"
end

class Sub < Base
  def sub_kind = "sub"
end

class Sub                 # reopened bare: no superclass to disagree with
  def extra = "extra"
end

class Sub < Base          # restated, the same superclass
  def more = "more"
end

module Mixin
  def mixed = "mixed"
end

module Mixin              # a module reopened as a module
  def mixed_again = "again"
end

class Sub
  include Mixin
end

s = Sub.new
p s.kind
p s.sub_kind
p s.extra
p s.more
p s.mixed
p s.mixed_again
p Sub.superclass
p Mixin.class
