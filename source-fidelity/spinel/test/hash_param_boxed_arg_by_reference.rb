# A hash parameter a caller hands a boxed hash stays that caller's object:
# typing it from the body's writes cast the Hash.new(0) to another struct
# (or passed a converted copy the writes never reached)
def cnt(xs, hash)
  xs.each { |x| hash[x] = hash.fetch(x, 0) + 1 }
  hash
end
s = Hash.new(0)
p cnt(%w[a a b], s)
p s
