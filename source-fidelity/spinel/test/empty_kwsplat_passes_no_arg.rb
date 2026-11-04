# An empty `**h` passes no argument (Ruby 3): `m(1, **{})` is `m(1)`. A
# keyword list made only of `**` spreads degraded to one positional hash
# whenever the callee took no keywords, so an empty one arrived as a stray
# trailing `{}` -- in a *rest, and through Proc#call on every path.

def rest(*a) = a

full = { k: 1 }
empty = { k: 1 }
empty.delete(:k)

# 1. A method collecting a *rest.
p rest(1, **empty)                         #=> [1]
p rest(1, **full)                          #=> [1, {k: 1}]
p rest(**empty)                            #=> []

# 2. Two spreads, both empty or one full.
p rest(1, **empty, **empty)                #=> [1]
p rest(1, **empty, **full)                 #=> [1, {k: 1}]

# 3. Proc#call and Lambda#call with a fixed argument list.
pr = proc { |*a| a }
la = lambda { |*a| a }
p pr.call(1, **empty)                      #=> [1]
p la.call(1, **empty)                      #=> [1]
p pr.call(1, **full)                       #=> [1, {k: 1}]

# 4. Proc#call with a positional splat beside the keyword spread: generic
#    forwarding, `def f(*args, **kwargs) = blk.call(*args, **kwargs)`.
def fwd(*args, **kwargs) = proc { |*a| a }.call(*args, **kwargs)
p fwd(1, 2)                                #=> [1, 2]
p fwd(1, k: 2)                             #=> [1, {k: 2}]

# 5. A proc read back out of a Hash (a boxed callable), forwarding both.
class Registry
  def initialize
    @blocks = {}
  end

  def register(name, &blk) = (@blocks[name] = blk)

  def invoke(name, *args, **kwargs) = @blocks.fetch(name).call(*args, **kwargs)
end

r = Registry.new
r.register(:echo) { |*a| a }
p r.invoke(:echo, 1, 2)                    #=> [1, 2]
p r.invoke(:echo, 1, k: 3)                 #=> [1, {k: 3}]
