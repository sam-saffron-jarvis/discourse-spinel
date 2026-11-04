# `m(&pr)` where whether there IS a proc is decided at run time.
#
# Two things went wrong, and either one alone leaves the call broken.
#
# The guard first: a `&block` parameter used as a condition has its own arm
# in emit_cond, and that arm had two answers where the `blk.nil?` arm beside
# it has three. A forwarded real proc -- present exactly when its pointer is
# -- read as "no block", so `return f unless block` ran, the call answered
# that return's type, and the proc it had been handed went uncalled.
#
# Then the proc's own parameters: the value is poly, so nothing at the call
# site binds them to what the method yields, and the yield hands them over
# boxed. Typed from nothing, `proc { |x| x.path }` read `x` as the default
# scalar and asked an object for a method Integer has -- at run time, with
# nothing said at compile time. The composition and curry sites already widen
# a proc's parameters for this reason; a run-time-decided block is the same
# case, and the walker that finds the literal now follows a conditional's
# arms to reach one written as `cond ? nil : proc { ... }`.
class F
  def path = "a.img"
  def size = 5
end

def with_f(&block)
  f = F.new
  return f unless block
  yield f
end

taken = ARGV.length > 5

# nil at run time on this run, so the guarded return is what answers
pr_none = taken ? proc { |x| x.path } : nil
p with_f(&pr_none).class

# a proc at run time: the block runs and its value is the answer
pr_some = taken ? nil : proc { |x| x.path }
p with_f(&pr_some)

# the same proc answering a different type
pr_size = taken ? nil : proc { |x| x.size }
p with_f(&pr_size)

# a proc whose presence is STATIC keeps working: it is spliced, not boxed
always = proc { |x| x.path }
p with_f(&always)
p with_f { |x| x.size }
p with_f.class
