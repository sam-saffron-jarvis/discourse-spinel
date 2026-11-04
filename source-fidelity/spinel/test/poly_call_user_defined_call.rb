# Regression: a poly slot holding a Proc / Curry / bound Method alongside a
# user class that ALSO defines `call` (or `[]`). The poly method dispatch's
# cls_id switch enumerates user classes only, so a boxed Proc matched no arm
# and hit the raising default:
#   undefined method 'call' for an instance of Proc
# The dispatch now routes a runtime callable through the callable machinery
# ahead of the switch.
#
# Covered:
# (a) the reported shape: a Defer-like class stores blocks in an untyped array
#     and runs them in reverse
# (b) a Proc and a user class defining `call` in the same poly slot, with args
# (c) a Proc returning a String and a user class returning an Integer in the
#     same slot -- the poly result stays dynamic
# (d) `obj.()` and a lambda sharing the slot with the user class
# (e) a bound Method (self-less top-level and self-ful instance, int returns)
#     sharing the slot with the user class
# (f) Proc#[] sharing the slot with a user class defining `[]`
# (g) a curried Proc (the SP_BUILTIN_CURRY arm)
# (h) a shadowed `.call` with more positional args than the callable ABI
#     packs (17): the pre-arm must stand down so the user-class arm serves it
#
# The snapshot is generated with reference Ruby.

# (a) the reported shape.
class Defer
  def initialize
    @blocks = []
  end
  def add(&block)
    @blocks << block
  end
  def call
    i = @blocks.length - 1
    while i >= 0
      @blocks[i].call
      i -= 1
    end
  end
end

def defer_show(s)
  puts s
end

d = Defer.new
d.add { defer_show("first") }
d.add { defer_show("second") }
d.call

# (b) a Proc and a user class defining `call` in the same poly slot.
class Handler
  def initialize(tag)
    @tag = tag
  end
  def call(x)
    "handler:#{@tag}:#{x}"
  end
end

slot = [proc { |x| "proc:#{x}" }, Handler.new("h")]
puts slot[0].call(1)
puts slot[1].call(2)

# (c) mixed return types: a Proc returning a String and a user class whose
# `call` returns an Integer share the poly slot. The poly result must stay
# dynamic -- without the analyzer change the slot was typed from the user
# method (Integer) and the Proc's String result was coerced to 0.
class Number
  def call(x)
    x
  end
end

cslot = [proc { |x| "text" }, Number.new]
puts cslot[0].call(1)
puts cslot[1].call(7)

# (d) obj.() and a lambda sharing the slot with the user class.
lslot = [->(x) { "lambda:#{x}" }, Handler.new("l")]
puts lslot[0].(3)
puts lslot[1].(4)

# (e) a bound Method sharing the slot with the user class. `method(:m)` is a
# top-level (self-less) Method, holder.method(:bump) an instance (self-ful)
# one; both return Integer, the legacy ABI's supported shape.
def m(x)
  x + 1
end

class Holder
  def initialize
    @base = 10
  end
  def bump(x)
    @base + x
  end
end

holder = Holder.new
mslot = [method(:m), holder.method(:bump), Handler.new("m")]
puts mslot[0].call(4)
puts mslot[1].call(5)
puts mslot[2].call(6)

# (f) Proc#[] sharing the slot with a user class defining `[]`.
class Indexer
  def [](x)
    "indexer:#{x}"
  end
end

islot = [proc { |x| "boxed:#{x}" }, Indexer.new]
puts islot[0][6]
puts islot[1][7]

# (g) a curried Proc sharing the slot with the user class. The Curry reads
# its arguments from the poly-arg side channel, a distinct arm from a plain
# Proc's.
add = proc { |a, b| a + b }.curry
kslot = [add, Handler.new("c")]
puts kslot[0].call(3).call(4)
puts kslot[1].call(5)
puts kslot[0][6][7]

# (h) a shadowed call with 17 positional args. The callable ABI caps at
# sp_int[16], so the pre-arm declines (argc > 16) and the user-class switch
# arm handles the call; without the guard the emitted 17-element
# `(sp_int[16]){...}` failed the -Werror test build.
class Wide
  def call(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q)
    "#{a}-#{q}"
  end
end

wslot = [Wide.new]
puts wslot[0].call(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17)
