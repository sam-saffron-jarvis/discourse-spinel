# `when <object>` against a typed subject asks `object === subject`. A
# class without an === or == of its own answers the inherited one: a
# Struct's compares members, a Comparable's comes from its <=>, and a plain
# object's is identity. The comparison was the pointer compare for all
# three, so `when ORIGIN` never matched an equal Point.

Point = Struct.new(:x, :y)
ORIGIN = Point.new(0, 0)
def where(pt)
  case pt
  when ORIGIN then :origin
  when Point.new(1, 1) then :one
  else :else
  end
end
p where(Point.new(0, 0))
p where(Point.new(1, 1))
p where(Point.new(2, 2))
v = [Point.new(0, 0), 5][0]
p(case v when ORIGIN then :o else :x end)

class Money
  include Comparable
  attr_reader :cents
  def initialize(c) = @cents = c
  def <=>(o) = cents <=> o.cents
end
FIVE = Money.new(5)
def price(m)
  case m
  when FIVE then :five
  else :other
  end
end
p price(Money.new(5))
p price(Money.new(6))

class Plain; end
A = Plain.new
def plain(x)
  case x
  when A then :a
  else :other
  end
end
p plain(A)
p plain(Plain.new)
