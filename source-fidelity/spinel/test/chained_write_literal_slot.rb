# `a = b = 0` writes 0 to BOTH targets. A nested write node evaluates to its
# slot's unified type, so taking that as the value assigned to the outer
# target leaks the inner slot's other writes into it: where b later widened
# to Bignum, a was promoted with it and `return [a]` declared an Array of
# Integer while the body built a boxed one -- a C function whose result type
# is not what it returns, which does not compile. The bottom literal is
# written to each target in its own slot type instead.
def f(c)
  a = b = 0
  if c
    a = 1
    b = 2
  else
    a = 3
    b = 18446744073709551614
  end
  return [a, b]
end
p f(true)
p f(false)

# the nil-initialised shape: a and b stay nullable, and stay nil
def g(x)
  s0 = s1 = s2 = nil
  if x != 0
    s0 = 9
    s1 = 1
    s2 = 18446744073709551614
  end
  return [s0, s1, s2]
end
p g(1)
p g(0)

# the chain still assigns every target, whatever the literal
def h
  a = b = c = 7
  [a, b, c]
end
p h
def hf
  a = b = 1.5
  [a, b]
end
p hf
def hs
  a = b = :s
  [a, b]
end
p hs
def hb
  a = b = true
  [a, b]
end
p hb

# a String chain keeps object identity -- the literal is NOT re-emitted per target
def hstr
  a = b = "x"
  [a.equal?(b), a, b]
end
p hstr

# Under --int-overflow=promote the elements of the returned array are boxed
# while the declared return is still the typed array, so the conversion
# helper runs. It converted with sp_poly_to_i, whose answer for nil is 0, and
# a nullable local came back as 0 rather than nil.
def nilable(x)
  s0 = s1 = nil
  if x != 0
    s0 = 9
    s1 = 1
  end
  return [s0, s1]
end
p nilable(1)
p nilable(0)
def nilable_f(x)
  a = nil
  a = 1.5 if x != 0
  return [a]
end
p nilable_f(1)
p nilable_f(0)
