# Regression for the poly-slot bound-Method return kinds (#4395 review
# follow-up).
#
# A bound Method read out of a poly slot used to be callable only when its
# target returned an sp_int-register value. A String-returning method, a
# nil-returning method (whose C return is `void`), and a reference-type object
# return all declined with NoMethodError even though CRuby answers them; a
# plain `def s` returns `const char *` just like the synthesized wrapper, so it
# is boxed by the String kind too, and a Bigint return is a nullable
# `sp_Bigint *` riding the register. The typed-array adapter's statically
# dispatched `.call` handed the raw sp_int register back as an Integer instead
# of casting it to the array/string it really is, and its `.arity` was nil. A
# splatted call on a bound Method in a poly slot read the Method as an sp_Proc
# and segfaulted; the spread now dispatches on the value's class.
#
# Every printed line is CRuby-equal; the snapshot comes from reference Ruby.

class Ret
  def str(a) = a > 0 ? "pos" : "neg"
  def nul = nil
  def sum2(a, b) = a + b
end

# String return through the poly `.call`/`[]` paths and the generic trampoline
r = Ret.new
sslot = [r.method(:str)]
puts sslot[0].call(1)
puts sslot[0].call(-1)
puts sslot[0][2]
puts sslot[0].to_proc.call(1)

# nil return (the target's C return is void)
nslot = [r.method(:nul)]
puts nslot[0].call.inspect
puts nslot[0].to_proc.call.inspect

# reference-type object return: a subclass makes the class a heap reference
class ObjBase
  def initialize = @v = 5
  def v = @v
end
class ObjSub < ObjBase; end
class ObjMaker
  def make = ObjSub.new
end
oslot = [ObjMaker.new.method(:make)]
puts oslot[0].call.class
puts oslot[0].call.v
puts oslot[0].to_proc.call.class

# arbitrary-precision integer return (an sp_Bigint *)
# (the argument keeps the `.call`/`[]`/`.to_proc` arities uniform)
class BigRet
  def big(n) = 2 ** 100 + n
end
bslot = [BigRet.new.method(:big)]
puts bslot[0].call(0)
puts bslot[0].call(0).to_s.length
puts bslot[0][0]
puts bslot[0].to_proc.call(0)
# The wrong-count guard answers a Bigint-returning target's default value
# (NULL), not an int where the callee's C type is `sp_Bigint *` -- the latter
# made the generated translation unit fail to compile.
begin
  BigRet.new.method(:big).call
rescue ArgumentError
  puts "big_arity: ArgumentError"
end

# typed-array adapter static `.call`: the raw sp_int register is cast back to
# the array/string it really is, and the adapter reports CRuby's arity
ia = [1, 2]
puts ia.method(:push).call(3).inspect
puts ia.inspect
puts ia.method(:[]=).call(0, 7).inspect
puts ia.inspect
puts ia.method(:[]).call(1).inspect
puts ia.method(:[]).call(9).inspect
puts ia.method(:push).arity
puts ia.method(:[]=).arity
puts ia.method(:[]).arity
sa = ["x"]
puts sa.method(:push).call("y").inspect
puts sa.inspect
puts sa.method(:[]=).call(0, "z").inspect
puts sa.inspect
puts sa.method(:[]).call(0).inspect
puts sa.method(:[]).call(9).inspect
puts sa.method(:push).arity
puts sa.method(:[]=).arity
puts sa.method(:[]).arity
# the same adapter read back out of a poly slot also reports its arity
pslot = [sa.method(:push)]
puts pslot[0].call("w").inspect
puts pslot[0].arity.inspect

# static adapter `.call` with a runtime splat: the argument count is dynamic,
# so the adapter expands it against its fixed arity and launders each element
# (previously the splat was passed as one sp_int argument, which emitted an
# `sp_int = sp_PolyArray *` initializer and did not compile)
ia2 = [1, 2]
ia2_args = [3]
puts ia2.method(:push).call(*ia2_args).inspect
puts ia2.inspect
ia2_set = [0, 7]
puts ia2.method(:[]=).call(*ia2_set).inspect
puts ia2.inspect
sa2 = ["x"]
sa2_args = ["y"]
puts sa2.method(:push).call(*sa2_args).inspect
puts sa2.inspect
sa2_set = [0, "z"]
puts sa2.method(:[]=).call(*sa2_set).inspect
puts sa2.inspect
puts sa2.method(:[]).call(*[0]).inspect

# A fixed argument BEFORE a runtime splat still occupies adapter slot 0, so
# each splat element is tagged by its ABSOLUTE position: for `[]=` the splat's
# first element is the VALUE, not the index (`call(0, *["z"])` used to raise
# TypeError by laundering the String as the index)
sa5 = ["x", "y"]
puts sa5.method(:[]=).call(0, *["z"]).inspect
puts sa5.inspect
ia6 = [1, 2]
puts ia6.method(:[]=).call(0, *[7]).inspect
puts ia6.inspect

# `Array#push` is variadic: the fixed-arity adapter must be invoked once per
# value (a single call silently dropped every value after the first)
ia3 = [1, 2]
puts ia3.method(:push).call(3, 4).inspect
puts ia3.inspect
ia4 = [1, 2]
puts ia4.method(:push).call(*[3, 4]).inspect
puts ia4.inspect
ia5 = [1, 2]
puts ia5.method(:push).call(*[3], 5).inspect
puts ia5.inspect
sa3 = ["x"]
puts sa3.method(:push).call("y", "z").inspect
puts sa3.inspect
sa4 = ["x"]
puts sa4.method(:push).call(*["y", "z"]).inspect
puts sa4.inspect

# splat on a bound Method in a poly slot: the argument count is only known at
# run time, so the spread dispatches on the value's class (a Method through
# the generic trampoline, not cast to an sp_Proc)
def top_add2(a, b) = a + b
r2 = Ret.new
tslot = [r2.method(:sum2), method(:top_add2)]
argsv = [1, 2]
puts tslot[0].call(*argsv)
puts tslot[1].call(*argsv)
puts tslot[0][*argsv]
puts tslot[1].to_proc.call(*argsv)

# A trailing runtime splat into a statically-bound fixed-arity Method now
# validates the run-time count (CRuby's ArgumentError) and fills a literal
# optional default for a short splat instead of reading past the array.
class OptSplat
  def two(a, b) = a + b
  def opt(a, b = 10) = a + b
end
op = OptSplat.new
puts op.method(:opt).call(*[1])
puts op.method(:opt).call(*[1, 2])
begin
  op.method(:two).call(*[1])
rescue => e
  puts "short: #{e.class}"
end
begin
  op.method(:two).call(*[1, 2, 3])
rescue => e
  puts "long: #{e.class}"
end

# A class method's C ABI is self-less, but `.to_proc` selected the self-ful
# cast from the syntactic receiver and passed the Method's NULL self as
# argument 0, shifting every parameter; a bare `method(:sym)` in an instance
# method is the mirror case (it binds the enclosing self but names no
# receiver). Both must pick the ABI from the Method's persisted recv_bound.
class KlassMethod
  def self.cm(a, b) = [a, b]
end
puts KlassMethod.method(:cm).to_proc.call(2, 3)

class BareBound
  def m(a, b) = [a, b]
  def go
    method(:m).to_proc.call(2, 3)
  end
end
puts BareBound.new.go.inspect

# An already-optional positional default and a declared optional keyword
# default are evaluated, not read from an unset register.
class KwDefaults
  def kw(a, b = a + 1, c: 3) = [a, b, c]
end
puts KwDefaults.new.method(:kw).to_proc.call(1).inspect

# A declared optional keyword AFTER a rest takes its default through
# `.to_proc`: every positional past the fixed ones belongs to the rest array,
# so `call(1, 2, 9)` must leave `c` at 3 with the rest capturing [2, 9] (the
# trampoline used to read args[2] as the keyword value)
class RestTailKw
  def m(a, *r, c: 3) = [a, r, c]
end
puts RestTailKw.new.method(:m).to_proc.call(1, 2, 9).inspect
puts RestTailKw.new.method(:m).to_proc.call(1).inspect

# A default in a module method that reads an ivar of the INCLUDING class: the
# module scope types the add poly while the emitted field is concrete. A BARE
# `@x` default is the same shape without the arithmetic, whose default node is
# emitted as the raw field -- the boxing has to happen for it too.
module IvarDefault
  def mm(a, b = @x + a) = [a, b]
  def mbare(a, b = @x) = [a, b]
end
class IvarHost
  include IvarDefault
  def initialize = @x = 20
end
puts IvarHost.new.method(:mm).call(1).inspect
puts IvarHost.new.method(:mm).to_proc.call(1).inspect
puts IvarHost.new.method(:mbare).call(1).inspect
puts IvarHost.new.method(:mbare).to_proc.call(1).inspect

# A bare `method(:sym)` in an INSTANCE method (no syntactic receiver) whose
# default reads an ivar: the Method binds the enclosing self, so both the
# `.call` and `.to_proc` routes must evaluate the default against the bound
# receiver, not the caller's self or an undeclared `self`.
class BareIvarDefault
  def initialize(x) = @x = x
  def m(a, b = @x + a) = [a, b]
  def go_call = method(:m).call(1)
  def go_proc = method(:m).to_proc.call(1)
end
b = BareIvarDefault.new(20)
puts b.go_call.inspect
puts b.go_proc.inspect

# Two allocating defaults on one bound Method: each default is evaluated into a
# call-local temp, and the later default's allocation (the 400-element Array)
# must not collect the earlier default's String. The corruption showed up after
# a handful of iterations, so a loop is the regression: neither route may
# answer a garbage length.
class TwoDefaults
  def m(a, b = "x" * 64, c = Array.new(400) { |i| i.to_s }) = [b.length, c.length]
end
td = TwoDefaults.new
all = true
200.times { |i| all &&= (td.method(:m).call(i) == [64, 400]) }
200.times { |i| all &&= (td.method(:m).to_proc.call(i) == [64, 400]) }
puts "two_defaults: #{all}"

# A default containing an inlined iterator block binds its block parameter
# through a METHOD-scope local (`lv_x`). The `.to_proc` trampoline is a
# separate C function with no method prologue, so it must declare those
# block-param locals itself; without this the generated trampoline referred to
# an undeclared `lv_x` and the C build failed. The block may also read an
# earlier parameter (`x + a`), which the trampoline aliases.
class BlockDefault
  def m(a, c = [1, 2].map { |x| x }) = [a, c]
  def s(a, c = [1, 2, 3].select { |x| x > 1 }) = [a, c]
  def t(a, c = 3.times.map { |x| x + a }) = [a, c]
  def e(a, c = [1, 2].each { |x| x }) = [a, c]
end
bd = BlockDefault.new
puts bd.method(:m).to_proc.call(1).inspect
puts bd.method(:s).to_proc.call(1).inspect
puts bd.method(:t).to_proc.call(1).inspect
puts bd.method(:e).to_proc.call(1).inspect
puts bd.method(:m).call(1).inspect
puts bd.method(:t).call(1).inspect

# The same frame has to declare every OTHER local the default's inline emitter
# can name, not just the block parameter: a block-local (`|x; z|`), a
# destructured parameter (`|(x, y)|`), a local the default itself creates
# (`c = (q = ...; ...)`), and a captured block-local a nested proc closes over.
# Without the declarations the `.to_proc` trampoline (and the bound `.call`
# statement expression) referred to undeclared names and the C build failed.
class BlockDefaultShapes
  def bl(a, c = [1, 2].map { |x; z| z = x + a; z }) = [a, c]
  def ds(a, c = [[1, 2]].map { |(x, y)| x + y + a }) = [a, c]
  def q(a, c = (q = a + 5; q * 2)) = [a, c]
  def pr(a, c = [1, 2].map { |x| proc { x + a } }) = [a, c.map(&:call)]
end
bs = BlockDefaultShapes.new
puts bs.method(:bl).to_proc.call(1).inspect
puts bs.method(:ds).to_proc.call(1).inspect
puts bs.method(:q).to_proc.call(1).inspect
puts bs.method(:pr).to_proc.call(1).inspect
puts bs.method(:bl).call(1).inspect
puts bs.method(:ds).call(1).inspect
puts bs.method(:q).call(1).inspect
puts bs.method(:pr).call(1).inspect

# An OMITTED `**kwrest` at a bound `.call` must be CRuby's empty hash, not the
# NULL default the slot got on its own (the callee dereferenced NULL and
# crashed). A positional over-count call that raises must not poison the
# kwrest's inferred type with the scalar argument kind either: it used to make
# the later keyword-hash call emit `sp_int = sp_SymPolyHash *` (a C build
# failure). The statically bound and the splatted forms both answer CRuby.
class KwRestEmpty
  def m(a, **k) = [a, k]
end
begin
  KwRestEmpty.new.method(:m).call(1, 2)
rescue ArgumentError
  puts "kwrest_over: ArgumentError"
end
puts KwRestEmpty.new.method(:m).call(1).inspect
puts KwRestEmpty.new.method(:m).call(1, z: 2).inspect
puts KwRestEmpty.new.method(:m).call(1, z: 2, w: 3).inspect
puts KwRestEmpty.new.method(:m).call(*[1]).inspect
begin
  KwRestEmpty.new.method(:m).call(*[1, 2])
rescue ArgumentError
  puts "kwrest_splat_over: ArgumentError"
end
