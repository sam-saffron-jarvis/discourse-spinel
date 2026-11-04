# A call through a Method object binds its arguments to the target's
# parameters the way a call by name does: an omitted optional takes its
# default, a rest parameter takes the surplus as one array, a keyword lands
# in its slot, a splat spreads, and a count the target cannot take is CRuby's
# ArgumentError -- for Method#call, [], .(), ===, a Method passed with &,
# and the Proc Method#to_proc answers.

def bad
  yield
  puts "no error"
rescue ArgumentError => e
  puts "#{e.class}: #{e.message}"
end

def rest(*v) = v.length
def lead(a, *v) = [a, v]
def opt(a, b = 2) = a + b
def opts(a, b = 2, c = "x") = [a, b, c]
def kw(x:, y: 1) = x + y
def zero = 0
def two(a, b) = a * b
def keep(&b) = b

# --- a top-level target, called through the Method object

p method(:rest).call, method(:rest).call(1, 2, 3), method(:rest)[1, 2], method(:rest).(1)
p method(:lead).call(1), method(:lead).call(1, 2, 3)
p method(:opt).call(1), method(:opt).call(1, 5), method(:opts).call(1), method(:opts).call(1, 5, "y")
p method(:kw).call(x: 2), method(:kw).call(x: 2, y: 3)
p method(:opt) === 1, method(:two).call(2, 3)
a = [1, 2]
p method(:rest).call(*a), method(:two).call(*a), method(:opt).call(*[1]), method(:lead).call(*a, 3)
p [[2, 3], [4, 5]].map { |pr| method(:two).call(*pr) }, [a].map { |x| rest(*x) }, [a].map { |x| two(*x) }
$feeds = 0
def feed(n) = ($feeds += 1; n > 0 ? [5, 6] : 7)
p rest(*feed(1)), method(:rest).call(*feed(1)), $feeds
p method(:keep).call { 7 }.call, method(:keep).call.nil?
m = method(:opt)
p m.call(1), m[1, 1]

bad { method(:zero).call(1) }
bad { method(:opt).call }
bad { method(:opt).call(1, 2, 3) }
bad { method(:two).call(1) }
bad { method(:lead).call }
bad { lead }
# A keyword hash passed to a target with NO declared keyword parameter is a
# positional (Ruby packs it), so it still counts against the positional range.
bad { method(:two).call(1, 2, c: 3) }
bad { method(:two).call(c: 3) }

# A declared keyword parameter is not positional, so the count guard judges
# only the positional range even when the target has one: a positional under-
# or over-count still raises ArgumentError, while a keyword hash binds by name.
class KwCount
  def kw(a, b = a + 1, c: 3) = [a, b, c]
  def kwreq(a, c:) = [a, c]
  def kwh(a, c: 3) = [a, c]
end
kc = KwCount.new
bad { kc.method(:kw).call }
bad { kc.method(:kw).call(1, 2, 3, 4) }
p kc.method(:kw).call(1), kc.method(:kw).call(1, 2), kc.method(:kw).call(1, c: 9)
# A keyword hash binds by name and is NOT counted as a positional, so omitting
# the required positional must still raise -- `given 0`, not the hash count.
bad { kc.method(:kwreq).call(c: 9) }
bad { kc.method(:kwreq).call(1, 2, c: 9) }
p kc.method(:kwreq).call(1, c: 9)
# An explicit BRACED hash is a positional HashNode, not a KeywordHashNode, so
# it binds to the positional `a` and leaves `c` at its default; a second
# positional is then an over-count (CRuby: `[{c: 9}, 3]`, then ArgumentError).
p kc.method(:kwh).call({c: 9})
bad { kc.method(:kwh).call(1, {c: 9}) }
# A keyword hash passed to a target with NO declared keyword parameter is a
# positional Hash even when its key spells a positional parameter's name: it
# binds to that parameter AS THE HASH (`[{a: 1}]`), it is not unpacked by name
# (that would feed the value node to a hash-typed slot).
class NoKwName
  def m(a) = [a]
end
nkn = NoKwName.new
p nkn.method(:m).call(a: 1)
p nkn.method(:m).call({a: 1})

# --- a caller local that shares a callee local's name is not captured by the
# callee-local declarations in the bound `.call` frame; the argument expression
# must read the caller's binding, and the callee's default must not write it.
class ShadowDef
  def m(a, b = 2) = (x = a + b; [a, x])
  def s(a, b = 2) = (s = "callee"; [a, b, s])
  def kw(a, c: 3) = (s = 9; [a, c, s])
  def cp(a, c = (qq = a + 1; proc { qq })) = [a, c.call]
end
sh = ShadowDef.new
x = 100
p sh.method(:m).call(1, x), x
s = 100
p sh.method(:s).call(1, s), s
p sh.method(:kw).call(1, c: s)
qq = 100
p sh.method(:cp).call(1), qq

# --- passed with &: the block's argument goes through the same binding

p [1, 2].map(&method(:opt)), [[1, 2], [3, 4]].map(&method(:rest)), %w[a b].map(&method(:rest))

# --- the Proc a Method answers binds its arguments the same way

pr = method(:rest).to_proc
po = method(:opts).to_proc
pl = method(:lead).to_proc
p pr.call, pr.call(1, 2), pr.lambda?, pr.arity
p po.call(1), po.call(1, 5), po.call(1, 5, "y"), po.arity
p pl.call(1), pl.call(1, 2, 3), pl.arity
p [1, 2].map(&po), [[1, 2], [3]].map(&pl)
bad { pr.call }
bad { po.call }
bad { po.call(1, 2, 3, 4) }
bad { pl.call }
bad { method(:two).to_proc.call(1) }
bad { method(:zero).to_proc.call(1) }

# --- a Proc-typed parameter: the sp_int proc slot launders the pointer, both
# for an explicit argument and for one a default fills in
class ProcParam
  def q(a, c = proc { a }) = [a, c.call]
  def r(a, c) = [a, c.call]
end
pp = ProcParam.new
p pp.method(:q).call(5), pp.method(:q).to_proc.call(5)
p pp.method(:r).call(5, proc { 99 }), pp.method(:r).to_proc.call(5, proc { 99 })

# --- a poly class receiver dispatches a class method by its run-time tag

class CA
  def self.tag(a, b) = "CA#{a}#{b}"
end
class CB
  def self.tag(x, y, *rest) = "CB#{x}#{y}#{rest.length}"
end
[CA, CB, 1].each do |m|
  begin
    p m.tag(1, 2)
  rescue NoMethodError
    puts "NoMethodError"
  end
end
sp = [7, 8, 9]
p [CB].map { |m| m.tag(*sp) }
two = [CA, CB]
p two.map { |m| m.tag(3, 4) }
[CB].each do |m|
  begin
    p m.tag(1)
  rescue NoMethodError, ArgumentError
    puts "count error"
  end
end

# --- a bound builtin's Method carries its arguments through unlisted

p "a b".method(:split).call(" "), [3, 1].method(:rotate).call(1)
p "a b".method(:split).to_proc.call(" "), [1, [2]].method(:flatten).to_proc.call(1)

# --- an object-bound target: the same binding, and the count checked

class K
  def initialize(base) = @base = base
  def r(*v) = [@base, v]
  def o(a, b = 2) = @base + a + b
  def w(x, y = 1.5) = [x, y]
  def k(x:, y: 1) = @base + x + y
  def z = @base
  def show(v) = (puts "show #{v}"; v)
end
k = K.new(10)
p k.method(:r).call, k.method(:r).call(1, 2), k.method(:o).call(1), k.method(:o).call(1, 5)
p k.method(:k).call(x: 2), k.method(:k).call(x: 2, y: 3), k.method(:z).call
p k.method(:z).unbind.bind(K.new(20)).call
p [1, 2].map(&k.method(:o))

bad { k.method(:z).call(1) }
bad { k.method(:o).call }
bad { k.method(:o).call(1, 2, 3) }
p k.method(:r).to_proc.call(1, 2)

kr = k.method(:r).to_proc
ko = k.method(:o).to_proc
kw = k.method(:w).to_proc
p kr.call, kr.call(1, 2), ko.call(1), ko.call(1, 5), kw.call(2), kw.call(2, 0.25)
bad { ko.call }
bad { ko.call(1, 2, 3) }
bad { kw.call }
bad { k.method(:z).to_proc.call(1) }

# --- the receiver and the arguments are evaluated, in order, before the raise

bad { k.method(:show).call(k.show(1), k.show(2)) }
bad { k.method(:z).call(k.show(3)) }
