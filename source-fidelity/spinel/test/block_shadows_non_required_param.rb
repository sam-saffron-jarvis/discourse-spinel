# A block parameter or block-local (`|x; q|`) that shadows a method
# parameter gets its own slot for every parameter kind, not only a
# required one. Shadowing an optional or keyword parameter wrote the
# method's own variable; shadowing `*q`, `**q` or `&q` shared its C slot
# at a different C type and did not compile.

def opt_local(q = 7)
  [1, 2].each { |x; q| q = x * 100; p q }
  q
end
def rest_local(*q)
  [1, 2].each { |x; q| q = x * 100; p q }
  q
end
def kw_local(q: 7)
  [1, 2].each { |x; q| q = x * 100; p q }
  q
end
def kreq_local(q:)
  [1, 2].each { |x; q| q = x * 100; p q }
  q
end
def kwrest_local(**q)
  [1, 2].each { |x; q| q = x * 100; p q }
  q.size
end
def blk_local(&q)
  [1, 2].each { |x; q| q = x * 100; p q }
  q.call(5)
end

def rest_param(*q)
  [1, 2].each { |q| p q * 100 }
  q
end
def kwrest_param(**q)
  [1, 2].each { |q| p q * 100 }
  q.size
end
def blk_param(&q)
  [1, 2].each { |q| p q * 100 }
  q.call(5)
end

p opt_local
p rest_local(1)
p kw_local
p kreq_local(q: 4)
p kwrest_local(a: 1)
p blk_local { |v| v + 1 }
p rest_param(1)
p kwrest_param(a: 1)
p blk_param { |v| v + 1 }
