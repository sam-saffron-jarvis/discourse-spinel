# A failed comparison in Array#min/#max/#minmax over a boxed array names the
# accumulator first, the way CRuby's Array#min does (not its literal-array
# VM shortcut): "comparison of <accumulator class> with <new element> failed".
def t; yield; rescue ArgumentError => e; puts e.message; end
a = [1, "a"]; t { a.min }; t { a.max }; t { a.minmax }
b = ["a", 1]; t { b.min }; t { b.max }
c = [1, nil]; t { c.min }; t { c.max }
d = [nil, 1]; t { d.min }
class K; include Comparable; attr_reader :v; def initialize(v); @v = v; end; def <=>(o); o.is_a?(K) ? @v <=> o.v : nil; end; end
e = [K.new(1), 2]; t { e.max }
f = [2, K.new(1)]; t { f.min }
g = [K.new(1), K.new(2), nil]; t { g.max }
