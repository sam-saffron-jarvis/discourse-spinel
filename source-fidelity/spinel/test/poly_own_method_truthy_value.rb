# The class arm of a block call on a value that may be an Array or an
# object whose own any? answers a non-Boolean is typed by that method (#4952)
class Result
  def initialize(rows) = @rows = rows
  def to_a = @rows
end

class Bag
  def initialize(v) = @v = v
  def any? = @v
end

class Ctl
  def initialize(k)
    @rows = case k
            when 0 then [1, 5]
            when 1 then Result.new([2])
            else Bag.new("x")
            end
  end

  def show
    shown = @rows.any? { |x| x > 3 }
    shown ? "yes" : "no"
  end
end

p Ctl.new(0).show
p Ctl.new(2).show
