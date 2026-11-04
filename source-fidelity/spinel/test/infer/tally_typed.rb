# tally over an Integer array answers an Integer-keyed count hash, not a
# boxed one: the `hash = nil` parameter no call passes folds its arm away
p [1, 2, 2, 3].tally
p %w[a b a].tally
