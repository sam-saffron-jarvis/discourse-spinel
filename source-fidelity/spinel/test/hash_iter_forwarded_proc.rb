# A Hash iterator handed a callable VALUE with `&`.
#
# `h.each(&f)` worked and `h.map(&f)` raised NoMethodError at run time, on a
# program that compiled. The two go through the same desugar -- `recv.<iter>(&f)`
# becomes `recv.<iter> { |a, b| f.call(a, b) }` -- and it asks ty_block_yield
# how many values the iterator yields. That oracle listed `each`, `each_pair`,
# `each_key` and `each_value` for a Hash and nothing else, so every other
# Enumerable name read back as 0, which the desugar takes to mean "not an
# iterator" and declines on. Declining left the call in its &-form with no
# emitter to claim it, and the unresolved call raised at run time naming a
# method Hash plainly has.
#
# A Hash gets these names from Enumerable and hands all of them the same
# [k, v] pair `each` does, so the rule is one line and not a list of cases.
# What separates a 1-param callable (which gets the pair as one array) from a
# 2-param one (which gets k and v positionally) is the wrap_pair rule at the
# call site, which `each` already exercised.
#
# The arms below are the ones that reach the desugar: the callable has to be a
# reference the compiler can re-read per element (a local or an ivar), and its
# arity has to be visible. `&proc { }` written at the call site is a literal
# block by another spelling and never reaches this path at all.
h = { "a" => 1, "b" => 2 }

two = proc { |k, v| "#{k}=#{v}" }
one = proc { |pair| pair.inspect }
lam = lambda { |k, v| k }

p h.map(&two)
p h.map(&one)
p h.map(&lam)
p h.select(&proc { |k, v| v > 1 })
p h.reject(&two).size
p h.any?(&proc { |k, v| v > 1 })
p h.all?(&proc { |k, v| v > 0 })
p h.count(&proc { |k, v| v > 1 })
p h.sort_by(&proc { |k, v| -v })
p h.find(&proc { |k, v| v == 2 })
p h.group_by(&proc { |k, v| v.odd? })
p h.partition(&proc { |k, v| v > 1 })
p h.min_by(&proc { |k, v| v })
p h.flat_map(&proc { |k, v| [k, v] })
p h.filter_map(&proc { |k, v| v > 1 ? k : nil })

# each still answers the receiver, which is what made the gap visible: the two
# names differ only in the value, and only one of them worked.
seen = []
h.each(&proc { |k, v| seen << k })
p seen

# An Array receiver never had the gap (its oracle arm covers the whole family),
# and must not move.
xs = [1, 2, 3]
dbl = proc { |v| v * 2 }
p xs.map(&dbl)
p xs.select(&proc { |v| v > 1 })
