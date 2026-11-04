# A constructor whose default argument is a frozen empty Hash constant, called
# through a Class-typed slot (#4510). `{}.freeze` binds the same literal as
# `{}`, and an empty hash constant takes its key type from the parameters that
# default to it (`attrs[:x]` says Symbol), so the constructor's parameter
# and the Symbol-keyed argument agree and the dispatch has an arm for S.
EMPTY = {}.freeze
class S
  def initialize(attrs = EMPTY) = (@a = (attrs[:x] || 0).to_i)
  def a = @a
end
def build(k, h) = k.new(h)
def build0(k) = k.new
p build(S, {x: 1}).a
p build0(S).a
p EMPTY.frozen?
p EMPTY.empty?

# the unfrozen and the non-empty forms keep working
DEF = {}
class T
  def initialize(opts = DEF) = (@n = (opts[:n] || 7).to_i)
  def n = @n
end
p build(T, {n: 2}).n
p build0(T).n

# The constant spelled by its path, one hop and two (#4511): the parameter
# evidence reaches it by the leaf name the path node carries.
module AR
  class Base
    EMPTY_ATTRS = {}.freeze
  end
end
class U
  def initialize(attrs = AR::Base::EMPTY_ATTRS) = (@a = (attrs[:x] || 0).to_i)
  def a = @a
end
class V < AR::Base
  def initialize(attrs = EMPTY_ATTRS) = (@a = (attrs[:x] || 0).to_i)
  def a = @a
end
p build(U, {x: 3}).a
p build(V, {x: 4}).a
p AR::Base::EMPTY_ATTRS.frozen?
