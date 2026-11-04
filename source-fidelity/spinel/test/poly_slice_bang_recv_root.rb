# sp_PolyArray_slice_bang allocates its result and then reads its receiver's
# elements. The four typed slice! helpers root their receiver across that
# allocation; the poly one did not, and relied on its call sites. Before
# #4605 and #4606 rooted the receiver at the slice!(i, n) and slice!(range)
# call sites, a receiver straight from a method call was in no local and
# this test read 1163 and 978 wrong on e1c5f2ca under SPINEL_GC_STRESS=1.
# With the call sites rooting, it reads 0 with or without the helper's root;
# it guards the pair. The helper's own root is pinned by building this
# test's generated C with the eleven call-site roots stripped: master's
# header is wrong 1163 and 328 times, the rooted header 0 and 0.
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }

bad = 0
4000.times do
  r = polys.slice!(5, 3)
  bad += 1 if r != ["s6", 70, "s8"]
end
p bad

# the same helper behind slice!(range), shift(n) and pop(n)
bad = 0
1000.times do
  bad += 1 if polys.slice!(2..4) != [30, "s4", 50]
  bad += 1 if polys.shift(2) != [10, "s2"]
  bad += 1 if polys.pop(2) != [390, "s40"]
  bad += 1 if polys.slice!(-3, 2) != ["s38", 390]
end
p bad

# result shapes the helper answers on a fresh array
p polys.slice!(38, 5)
p polys.slice!(40, 1)
p polys.slice!(41, 1)
p polys.slice!(3, -1)
p polys.slice!(-41, 2)
begin
  polys.freeze.slice!(0, 1)
rescue => e
  puts e.class
end
