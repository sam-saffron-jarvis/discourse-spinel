# spinel: int64 -- assumes a 64-bit Integer (2**70 needs it)
# A poly value whose actual class is Integer or Bignum used to reach NO
# numeric implementation as soon as ANY class in the program defined a
# method of the same name, whatever its arity: the poly-dispatch collision
# switch (emit_poly_method_dispatch, codegen_call.c) built an arm per user
# class and none at all for the non-object tags, so an Integer/Bignum
# receiver fell to the switch's NoMethodError default. Covers the
# names newly given a default arm: bit_length, digits (0 and 1 arg), gcd,
# lcm, ceildiv, pow (1 and 2 args), allbits?/anybits?/nobits? -- both when
# the colliding class defines the name with the SAME arity as the call
# site and with a DIFFERENT one (a distinct code path: the switch used to
# decline to build at all when no user class matched the call site's own
# arity, second half below). gcdlcm also has a default arm now (see
# codegen_call.c) but is not exercised here: a colliding class whose own
# gcdlcm answers a different concrete shape than the builtin's array hits
# a separate, pre-existing return-type-unification gap in the poly
# dispatch's own case-arm boxing (confirmed identical on an unmodified
# compiler with `abs`/`even?`/`fdiv`, unrelated to this fix).

class Widget
  def bit_length = "widget"
  def digits(*a) = "widget-digits-#{a}"
  def gcd(x) = "widget-gcd"
  def lcm(x) = "widget-lcm"
  def ceildiv(x) = "widget-ceildiv"
  def pow(*a) = "widget-pow-#{a}"
  def allbits?(x) = "widget-allbits"
  def anybits?(x) = "widget-anybits"
  def nobits?(x) = "widget-nobits"
end

class WidgetDiffArity
  def gcd(x, y, z) = "diff-arity-gcd"
  def digits(a, b) = "diff-arity-digits"
end

def pick(v) = v

w = Widget.new
d = WidgetDiffArity.new

# the colliding class still answers for its own instances
p pick(w).bit_length
p pick(w).digits(2)
p pick(w).gcd(1)
p pick(w).lcm(1)
p pick(w).ceildiv(1)
p pick(w).pow(1)
p pick(w).allbits?(1)
p pick(w).anybits?(1)
p pick(w).nobits?(1)

# an Integer receiver still reaches the numeric implementation (same-arity collision)
p pick(255).bit_length
p pick(123).digits
p pick(123).digits(16)
p pick(6).gcd(4)
p pick(6).lcm(4)
p pick(7).ceildiv(2)
p pick(2).pow(10)
p pick(2).pow(10, 1000)
p pick(6).allbits?(2)
p pick(6).anybits?(1)
p pick(6).nobits?(1)

# a Bignum receiver too
p pick(2 ** 70).bit_length
p pick(2 ** 70).digits

# different-arity collision: the colliding class's own method does not match
# this call site's arity, so the numeric implementation still has to answer
p pick(d).gcd(1, 2, 3)
p pick(6).gcd(4)
p pick(d).digits(1, 2)
p pick(123).digits

# a name Integer does not have still raises NoMethodError for an Integer
# receiver, with the class named
begin
  pick(5).frobnicate
rescue NoMethodError => e
  p e.message
end

# String/Symbol/Array/Hash/nil receivers of a contested numeric name keep
# their own (raising) answer
[ "hi", :sym, [1, 2], { a: 1 }, nil ].each do |v|
  begin
    p pick(v).gcd(4)
  rescue NoMethodError
    p :nomethod
  end
end
