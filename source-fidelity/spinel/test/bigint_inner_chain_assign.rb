# The INNER write of an assignment chain whose target is a Bignum slot wraps
# its value, exactly as the statement form does: `b = a = 3` with `a` promoted
# to a Bignum by its self-multiply loop reinterpreted the raw 3 as an
# sp_Bigint*, and a boxed chain value did not build at all.
b = a = 3
i = 0
while i < 3
  a = a * a
  i += 1
end
b = b + 1
p a
p b
c = d = e = 2      # the Bignum slot in the middle of a longer chain
i = 0
while i < 3
  d = d * d
  i += 1
end
c = c + 1
e = e + 1
p [c, d, e]
