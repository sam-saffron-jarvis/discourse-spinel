# The chunk family answers an Enumerator whose size is nil, as CRuby's
# Generator-backed one does
p [1, 2].chunk_while { |a, b| true }.size
p [1, 2, 4].slice_when { |a, b| b > a + 1 }.size
e = [1, 2, 4].chunk_while { |a, b| b == a + 1 }
p e.size
p e.to_a.size
p e.count
p [1, 2].chunk { |x| x.odd? }.size
p [1, 2].slice_before { |x| x.even? }.size
p [1, 2].slice_after(&:even?).size
p [1, 2].each_slice(1).size
p [1, 2].each_entry.size
