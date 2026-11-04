# A slot that may hold a builtin Array (or Hash) OR a user object whose class
# defines the same name: the per-class dispatch carried an arm for the user
# class and none for the builtin, so the Array reached the raise -- naming
# Array, whose method it is (#4264). A blockless any? / none? asks whether
# there is an element, which every builtin container answers.
class Relation
  def initialize(rows)
    @rows = rows
  end

  def any?
    @rows.length > 0
  end

  def none?
    @rows.length == 0
  end

  def to_a
    @rows
  end
end

def pick(as_array, empty)
  rel = Relation.new(empty ? [] : [1, 2, 3])
  as_array ? rel.to_a : rel
end

p pick(true, false).any?
p pick(false, false).any?
p pick(true, true).any?
p pick(false, true).any?
p pick(true, false).none?
p pick(false, true).none?

# a Hash through the same slot
def hpick(as_hash)
  as_hash ? { "a" => 1 } : Relation.new([1])
end

p hpick(true).any?
p hpick(false).any?
p hpick(true).none?

# the user class still answers its own method where it is the value, and the
# block form is unaffected
p Relation.new([1]).any?
p [1, 2, 3].any? { |x| x > 2 }
p [1, 2, 3].none? { |x| x > 5 }
