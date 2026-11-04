# A block that reaches its callee as a `&blk` parameter and is stored for
# later captures the enclosing iteration block's PARAMETER: each iteration
# binds the parameter anew, so each stored proc keeps its own value. One
# shared cell for the parameter had every stored proc answer the last value
# (#4462: a thread-pool port's `post(&task)` delivered every task with the
# last subscription).
def keep(store, &blk)
  store.push(blk)
  nil
end

# the parameter itself
b = []
3.times { |i| keep(b) { i } }
p b.map { |pr| pr.call }

# a block-local derived from it (already per iteration)
c = []
3.times { |i| j = i * 2; keep(c) { j } }
p c.map { |pr| pr.call }

# through a nested block: the outer parameter and the inner one
r = []
2.times { |i| [7, 8].each { |j| keep(r) { [i, j] } } }
p r.map { |pr| pr.call }

# a string parameter
s = []
%w[a b].each { |w| keep(s) { w * 2 } }
p s.map { |pr| pr.call }

# the pool shape from the report
class Pool
  def initialize; @queue = []; end
  def post(&task); @queue.push(task); nil; end
  def run; @queue.map { |t| t.call }; end
end
pool = Pool.new
3.times { |i| pool.post { i * 10 } }
p pool.run

# the parameter reassigned in the body: the procs of that iteration share
# the reassignment (one cell per iteration), later iterations do not
q = []
3.times { |i| keep(q) { i }; i += 100; keep(q) { i } }
p q.map { |pr| pr.call }
t = []
3.times { |i| keep(t) { i }; i = i + 100 }
p t.map { |pr| pr.call }
u = []
2.times { |i| [1].each { |j| keep(u) { i }; i += 10 } }
p u.map { |pr| pr.call }
