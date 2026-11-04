# A method called with `&proc` inlines with its yields bound to the proc. A
# block that method hands to an inlined callee (`{ |x| yield x }`, which is
# what a forwarded `&b` becomes) carries that binding into the callee's
# splice: the yield there found no block, and where it did, its call was
# hoisted above the block parameter's binding and its tail dropped the value.
# A scalar block tail into the poly slot a yield was typed for is boxed.
def collect(xs)
  r = []
  xs.each { |x| r << yield(x) }
  r
end
def keyed(xs)
  h = {}
  xs.each { |x| (h[yield(x)] ||= []) << x }
  h
end
def fwd(&b) = collect([1, 2, 3], &b)
def fwd_keyed(&b) = keyed(["a", "bb", "c"], &b)

odd = ->(x) { x.odd? }
p fwd(&odd)
p(fwd { |x| x * 10 })
len = ->(s) { s.length }
p fwd_keyed(&len)
p(fwd_keyed { |s| s.upcase })
p(fwd_keyed { |s| s.size > 1 })
p collect([1, 2], &odd)
p keyed([1, 2, 3], &odd)
