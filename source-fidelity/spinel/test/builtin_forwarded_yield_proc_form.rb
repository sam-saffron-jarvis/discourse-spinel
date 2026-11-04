# A class whose `partition` forwards to a builtin on its `to_a`
# (`to_a.partition { |x| yield x }`), reached on a boxed receiver so the
# method takes its proc form: the forwarded yield inside the spliced block
# calls the proc, and the rooted temp for its argument is a prelude that
# belongs before the statement, not inside the call's argument list, where
# the splice once wrote it (#4662). The destructured answers, both call
# forms, and a second builtin forwarded the same way.
class Relation
  def initialize(rows) = @rows = rows
  def to_a = @rows
  def partition
    to_a.partition { |x| yield x }
  end
  def all?
    to_a.all? { |x| yield x }
  end
  def min_by
    to_a.min_by { |x| yield x }
  end
end
def poly(v) = v
poly("s")
r = poly(Relation.new([1, 2, 3, 4]))
a, b = r.partition { |m| m.odd? }
p a, b
p r.all? { |m| m > 0 }
p r.min_by { |m| -m }
r2 = Relation.new([5, 6])
x, y = r2.partition { |m| m > 5 }
p x, y
p r2.min_by { |m| m }
