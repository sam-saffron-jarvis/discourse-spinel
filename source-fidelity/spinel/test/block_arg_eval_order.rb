# A call with a block argument `&expr` evaluates its receiver, then its
# arguments, then the block expression, as Ruby does. The block went into the
# C call as one more function argument, or was hoisted ahead of a Class-value
# dispatch (#4992), and C leaves the order of function arguments to the
# compiler: the block's side effect came first.
def say(x)
  puts "arg #{x}"
  x
end

def blk(tag)
  puts "block #{tag}"
  proc { |v| v * 2 }
end

def run(a, &b) = b.call(a)
def run2(a, b, &c) = c.call(a + b)

class Obj
  def m(a, &b) = b.call(a)
end

class Ka
  def initialize(a, &b) = @b = b
  def poke(x) = @b.call(x)
end

class Kb
  def initialize(a, &b) = @b = b
  def poke(x) = @b.call(x + 1)
end

def pick(i) = i == 0 ? Ka : Kb
def mk(i) = pick(i).new(say(i), &blk(i))

p run(say(1), &blk(1))
p run2(say(2), say(3), &blk(2))
p Obj.new.m(say(4), &blk(4))
p [say(5)].map(&blk(5))
p Ka.new(say(6), &blk(6)).poke(5)
p mk(0).poke(5)
p mk(1).poke(5)
p run(say(7), &proc { |v| v + 1 })
