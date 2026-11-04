# `h = {}; yield h` hands the hash to a block the method does not see. The
# block fills it with keys this scope has no evidence of, and the empty
# literal's String-keyed default refused the store (`t[:a] = 1` raised
# TypeError). A yielded empty hash is the widest hash, as an empty hash
# passed to a yielding method already is.
def with_hash
  h = {}
  yield h
  h
end
p(with_hash { |t| t[:a] = 1 })
p(with_hash { |t| t["s"] = 2; t[3] = 4 })
def build
  yield({})
end
p(build { |t| t[:k] = :v; t })
def counts(words)
  h = {}
  words.each { |w| yield h, w }
  h
end
p(counts(%w[a b a]) { |acc, w| acc[w] = (acc[w] || 0) + 1 })
