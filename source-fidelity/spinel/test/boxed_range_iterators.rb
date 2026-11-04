# A boxed Range's map and first(n) answered [] silently, and select /
# filter / reject raised NoMethodError naming Range (#4837).

windows = Array.new(3) { |n| (60 + n)..(64 + n) }
p windows.map { |w| w.map { |c| c - 60 } }
p windows.map { |w| w.select { |c| c < 63 } }
r = [2..5, 1][0]
p r.map { |c| c * 10 }
p r.first(2)
p r.select(&:even?)
p r.filter(&:even?)
p r.reject(&:even?)
e = [(3..), 1][0]
p e.first(3)
x = [(2...5), 1][0]
p x.map { |c| c }
s = [("a".."d"), 1][0]
p s.map(&:upcase)
p s.select { |c| c > "b" }
[60..62, 70..71].each { |w| p w.map { |c| c + 1 } }
