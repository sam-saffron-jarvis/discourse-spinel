# A `then` block whose `next` arms answer arrays of another kind than the tail:
# the block's value is the poly array, and every arm converts into it.

# the reported shape: a poly-array tail (under --int-overflow=promote every
# Integer arithmetic result is boxed) beside a `next [v]` over the parameter
def pick(n)
  n.then do |v|
    next [] if v.zero?
    next [v] if v < 10
    [v, v * 2]
  end
end
p pick(0)
p pick(3)
p pick(20)

# the reverse: a typed tail, a mixed arm
def tag(n)
  n.then do |v|
    next [v, "big"] if v > 9
    [v]
  end
end
p tag(3)
p tag(30)

# two typed kinds
def name_or_id(n)
  n.then do |v|
    next ["anon", "x"] if v.negative?
    [v, v + 1]
  end
end
p name_or_id(-1)
p name_or_id(4)

# floats
def scale(f)
  f.then do |v|
    next [v] if v < 1.0
    [v, v * 0.5, "half"]
  end
end
p scale(0.25)
p scale(4.0)

# an empty-literal arm alone takes the tail's kind (unchanged)
def empty_or(n)
  n.then do |v|
    next [] if v.zero?
    [v, v + 1]
  end
end
p empty_or(0)
p empty_or(5)

# a splat arm
def spl(n)
  n.then do |v|
    next *[v, "s"] if v > 5
    [v]
  end
end
p spl(1)
p spl(9)
