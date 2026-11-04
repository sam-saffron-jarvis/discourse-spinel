# take, drop and insert root their receiver across their count argument.
#
# Each arm hoists the receiver into a temporary and then evaluates the
# count or index. When the receiver is a method's return, that temporary
# is the only reference to it, and an argument that allocates lets a
# collection run before the slice is cut. On master under
# SPINEL_GC_STRESS=1 the Integer take below answers [1, 2, 3, 4, 5], the
# Float take dies, the String drop answers a String from another array, the
# object drop answers 0 elements, insert splices into another array, the
# no-value insert answers another array, and Hash#drop answers 0 pairs.

class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end

# Allocates enough short-lived arrays of every kind that a freed slot is
# handed on before the caller reads it.
def churn
  (1..60).map { |i| [K.new(i), "s#{i}"] }
  (1..30).map { |i| [i, i.to_s] }
  (1..30).map { |i| i * 2 }
  (1..30).map { |i| "t#{i}" }
  nil
end

def idx; churn; 5; end
def neg; churn; -1; end
def val; churn; 99; end

def ints = (1..40).map { |i| i * 10 }
def floats = (1..40).map { |i| i * 1.5 }
def strs = (1..40).map { |i| "s#{i}" }
def objs = (1..40).map { |i| K.new(i) }
def polys = (1..40).map { |i| i.odd? ? i * 10 : "s#{i}" }
def table = (1..40).to_h { |i| ["k#{i}", i * 10] }

# take and drop, every array kind
p ints.take(idx)
p ints.drop(idx).first(3)
p floats.take(idx)
p strs.drop(idx).first
p objs.drop(idx).length
p objs.take(idx).map(&:v)

# the negative count still raises, after the argument ran
begin
  ints.take(neg)
rescue ArgumentError => e
  p e.message
end
begin
  ints.drop(neg)
rescue ArgumentError => e
  p e.message
end

# insert on the typed arms, with one value and with two
p ints.insert(idx, 99).first(7)
p strs.insert(idx, "y", "z").first(8)
p ints.insert(neg, 0).last(2)

# a value that allocates, after a constant index
p ints.insert(2, val).first(4)

# insert on a poly array with one value; an inline index that allocates
# is not bound ahead of the call, so the arm itself must hold the receiver
p polys.insert((churn; 2), 99).first(4)

# insert with no value answers the receiver, after the index has run
p ints.insert((churn; 2)).first(3)
p strs.insert((churn; 2)).first(3)
p objs.insert((churn; 2)).length
p polys.insert((churn; 2)).first(2)

# Hash#drop cuts its pairs after the count is evaluated
p table.drop(idx).length
p table.drop(idx).first
p table.drop(idx).last
