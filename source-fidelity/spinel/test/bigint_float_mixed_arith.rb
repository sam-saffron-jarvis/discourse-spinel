# A Bignum operand in float arithmetic converts to double -- the same reading
# the comparison path gives the pair -- instead of leaving an sp_Bigint* in a
# raw C float expression (which did not build). Both operand sides, and the
# %, ** and general arms; past int64 too, where the conversion really rounds.
l0 = 3
i = 0
while i < 3
  l0 = l0 * l0    # a self-multiply loop var stays a Bignum slot
  i += 1
end
p(l0 + 1.0)
p(1.0 + l0)
p(l0 / (Math.sqrt(l0 + 1.0) + 1.0))
p(l0 - 0.5)
p(2.5 * l0)
p(l0 % 7.0)
p(4.0 % l0)
p(l0 ** 0.5)
p(2.0 ** (l0 % 5))
while i < 6
  l0 = l0 * l0    # 3**64: past int64
  i += 1
end
p(l0 + 1.0)
p(l0 * 2.0)
