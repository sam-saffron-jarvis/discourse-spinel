# Proc#curry with no count realizes at the base's REQUIRED count -- CRuby's
# min arity -- so a variadic base invokes on its first call, however many
# arguments that call carries.
p ->(*v) { v.length }.curry.call
p ->(*v) { v.sum }.curry[5]
p ->(x, *r) { [x, r] }.curry.call(1)
p ->(x, y = 2) { [x, y] }.curry.call(1)

# A Method curries through the same machinery.
def count_values(*values)
  values.length
end
p method(:count_values).curry.call.class

# curry(nil) is the no-count spelling; a real count fixes the completion
# point, and a fixed-arity lambda validates it up front.
p proc { |x| x }.curry(nil).call(2)
begin
  ->(x) { x }.curry(2)
rescue ArgumentError => e
  p [e.class, e.message]
end
p ->(*v) { v.length }.curry(3).class
p ->(*v) { v.length }.curry(3)[1][2][3]
p proc { |x| x }.curry(5).class

# The count can be computed, or anything with a to_int -- and it is honored:
# a computed 3 on a two-parameter proc realizes at 3, leniently.
n = 2
add = ->(a, b) { a + b }
p add.curry(n)[3][4]
n3 = 3
pr = proc { |a, b| [a, b] }
p pr.curry(n3)[1][2][3]
class Arity
  def to_int
    1
  end
end
p proc { |value| value }.curry(Arity.new).call(7)
def count_values2(*values)
  values.length
end
p method(:count_values2).curry(Arity.new)[9]

# A computed count still validates against the lambda's min..max, the count
# expression may allocate while the fresh receiver waits, and non-Integer
# applications of a counted curry apply rather than index.
def alloc_two(x)
  ("a" * x).length
end
p ->(a, b) { a + b }.curry(alloc_two(2))[1][2]
begin
  cv = ->(x, y = 2) { }.curry(3)
  p cv.class
rescue ArgumentError => e
  p [e.class, e.message]
end
p ->(x, y = 2) { [x, y] }.curry(2)[7][8]
p add.curry(n)["x"]["y"]
p add.curry(n)[1.5][2.5]

# A count that arrives boxed is read at run time, CRuby's way: an Integer
# counts, nil is no count, anything else is the TypeError -- and the boxed
# path works even beside the user to_int above.
hc = { i: 2, f: 2.7, z: nil, s: "two" }
p add.curry(hc[:i])[3][4]
p add.curry(hc[:z])[3][4]
arr2 = [1, 2]
p add.curry(arr2[10])[1][2]
hA = { o: Arity.new, t: true }
p proc { |v| v }.curry(hA[:o]).call(7)
begin
  add.curry(hA[:t])
rescue TypeError => e
  p [e.class, e.message]
end
begin
  add.curry(hc[:s])
rescue TypeError => e
  p [e.class, e.message]
end
def no_count(tag)
  nil
end
p add.curry(no_count("a"))[1][2]

# The max sees a keyword hash as one more slot, a required-keyword hash
# counts once toward the min, and a mistraced max defers to the target.
begin
  cv = ->(a, **k) { a }.curry(5)
  p cv.class
rescue ArgumentError => e
  p [e.class, e.message]
end
k2 = ->(a, x:, y:) { [a, x, y] }
begin
  p k2.curry[1][2].class
rescue ArgumentError => e
  p e.class
end
sh = ->(x) { x }
sh = ->(a, b, e2) { a + b + e2 }
p sh.curry(3).call(1).call(2).call(3)

# A partial application keeps its manners: to_proc defers, a block-pass
# operand drives elementwise -- at any chain depth -- and a container call
# site completes. A realized value applied once more refuses loudly.
q4 = ->(a, b, c1, d) { a + b + c1 + d }.curry(idn = 4)
part3 = q4[1][2][3]
p [1, 2].map(&part3)
def keeper(&blk)
  blk.call(30)
end
p keeper(&q4[1][2][3])
begin
  proc { |*a| [a] }.curry(1)[1].call(2)
rescue NoMethodError => e
  p [e.class, e.message]
end
partial = add.curry(n)
part10 = partial[10]
p [1, 2, 3].map(&part10)
c2 = ->(a, b) { a + b }.curry
p c2.to_proc.call(1).class
g2 = { f: c2 }[:f]
p g2.call(1)[2]

# The completion count sees trailing posts and required keywords.
pz = ->(a, *r, z) { [a, r, z] }
p pz.curry[1][2]
kw = ->(a, b:) { [a, b] }
p kw.curry[1].class

# A curried proc travels through a container and keeps applying.
f = ->(a, b) { a + b }.curry
h = { f: f[1] }
p h[:f][2]

# Reflection: parameters is CRuby's [[:rest]] whatever the base; to_proc
# wraps the accumulator in a callable Proc.
c = ->(a, b) { a + b }.curry
p c.parameters
p c.to_proc.call(1, 2)
