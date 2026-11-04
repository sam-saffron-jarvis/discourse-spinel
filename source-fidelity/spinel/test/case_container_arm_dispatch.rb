# `case <array or hash> when <arm>` asks `arm === subject`: the arm is the
# receiver. An Array arm compares element by element with the arm's element
# on the left, so an element's own == is asked of the arm's side; an object
# arm whose class defines === is called with the Array or Hash. The subject
# may be an array of user objects as well as a builtin one.
class W
  def initialize(loose) = @loose = loose
  def ==(o) = @loose
end
arm_first = [W.new(true)]
subject = [W.new(false)]
p(case subject when arm_first then :arm_first else :subject_first end)
case subject
when arm_first then p [:stmt, :arm_first]
else p [:stmt, :subject_first]
end

class PairMatcher
  def ===(o) = o.is_a?(Array) && o.size == 2
end
m = PairMatcher.new
p(case [1, 2] when m then :pair else :other end)
p(case [1, 2, 3] when m then :pair else :other end)
p(case({a: 1}) when m then :pair else :other end)
case [3, 4]
when m then p [:stmt, :pair]
else p [:stmt, :other]
end
