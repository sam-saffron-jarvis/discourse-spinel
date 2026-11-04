# include? / index / rindex / count / delete on an Integer array given a
# boxed value that is not an Integer: TypeError or C that did not compile,
# where CRuby answers "not found" (#4835).

class K
  def initialize = @keys = []
  def m(row) = row.map { |key| @keys.include?(key) }
  def d(row) = row.map { |key| @keys.delete(key) }
end
p K.new.m(%i[a b])
p K.new.d(%i[a b])
ints = [1, 2]
[:a, "2", nil, 2].each do |v|
  x = [v, 1][0]
  p [ints.include?(x), ints.index(x), ints.count(x), ints.rindex(x)]
end
