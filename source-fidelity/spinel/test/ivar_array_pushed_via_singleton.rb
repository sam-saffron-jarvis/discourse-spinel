# An empty-[] ivar array passed to a SINGLETON method that pushes into it:
# the pass that widens an ivar shared with a push-widened parameter resolved
# receiverless and instance-method callees only, so a module function's push
# landed on the boxed int array and the element was coerced to its kind --
# [0] for a pushed "pushed" -- or dropped. Constant-receiver callees (and
# W.new's initialize) resolve now (#4213).
module Held
  def self.add(into)
    into.push("pushed")
  end

  def self.shove(into)
    into << :sym
  end
end

class Holder
  def initialize
    @found = []
  end

  def add
    Held.add(@found)
    Held.shove(@found)
  end

  def out = @found
end

h = Holder.new
h.add
p h.out

# The constructor spelling: W.new(@ivar) whose initialize pushes.
class Sink
  def initialize(bucket)
    bucket.push("from-init")
  end
end

class Keeper
  def initialize
    @rows = []
  end

  def fill
    Sink.new(@rows)
  end

  def out = @rows
end

k = Keeper.new
k.fill
p k.out

# A named ivar write before the call keeps working (the reporter's control).
class Named
  def initialize
    @a = [0]
  end

  def go
    Held.add(@a)
  end

  def out = @a
end

n = Named.new
n.go
p n.out

# An int-only helper keeps the typed representation.
module IntOnly
  def self.add(into)
    into.push(7)
  end
end

class NarrowKeep
  def initialize
    @n = [1]
  end

  def go
    IntOnly.add(@n)
  end

  def total = @n.sum
end

nk = NarrowKeep.new
nk.go
p nk.total
