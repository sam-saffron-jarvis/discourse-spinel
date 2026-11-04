# min_by / max_by / minmax_by walk the receiver once (a receiver that
# yields its elements only once), and Symbol keys compare as Symbols
class Once
  include Enumerable
  def initialize(xs) = @xs = xs
  def each
    x = @xs.shift
    while x
      yield x
      x = @xs.shift
    end
    self
  end
end
p Once.new([3, 1, 2]).min_by { |x| x }
p Once.new([3, 1, 2]).max_by { |x| x }
p Once.new([3, 1, 2]).minmax_by { |x| x }
calls = []
p [5, 4, 6].min_by { |x| calls << x; x }
p calls
p [:b, :a, :c].min_by { |x| x }
p [nil, :a].min_by { |x| x.nil? ? :z : x }
