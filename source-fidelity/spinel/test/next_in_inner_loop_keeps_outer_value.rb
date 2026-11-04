# A `next <value>` inside an inline loop nested in a block whose value is
# collected leaves the INNER loop's iteration; it is not the outer block's
# value. The outer block answers its own tail.

def each_in_then
  7.then do |v|
    [1, 2].each { |y| next [y, "n"] if y == 1 }
    [v]
  end
end
p each_in_then

def times_in_then
  7.then do |v|
    3.times { |y| next [y, "t"] if y == 1 }
    [v]
  end
end
p times_in_then

def while_in_then
  7.then do |v|
    i = 0
    while i < 2
      i += 1
      next [i, "w"] if i == 1
    end
    [v]
  end
end
p while_in_then

def hash_each_in_then
  7.then do |v|
    { "a" => 1 }.each { |k, x| next [k, x] if x == 1 }
    [v]
  end
end
p hash_each_in_then

# the kinds agree: the answer was right before, and stays so
def scalar_in_then
  7.then do |v|
    [1, 2].each { |y| next 99 if y == 1 }
    v + 1
  end
end
p scalar_in_then

r = [10, 20].map do |v|
  [1, 2].each { |y| next [y, "m"] if y == 1 }
  [v]
end
p r

# the inner next's expression still runs (#4235)
acc = [10, 20].map do |v|
  seen = []
  [1, 2].each { |y| next seen.push(y * v) if y == 1; seen.push(-y) }
  seen
end
p acc

# the outer block's own next is unaffected
q = [1, 2, 3].map do |v|
  next [v, "odd"] if v.odd?
  [0].each { |y| next [y, "z"] }
  [v]
end
p q
