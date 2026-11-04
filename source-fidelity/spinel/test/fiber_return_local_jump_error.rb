# A `return` written in a Fiber or Thread body cannot reach its home method:
# the body runs on its own stack. CRuby answers that shape with
# LocalJumpError -- whether the home method is still on the stack or not, and
# at the top level as well -- and carries the returned value as #exit_value.
#
# Spinel emitted a plain C return out of the fiber body instead, so the value
# was swallowed and the enclosing method carried on. (It was also a C
# constraint violation: the body is `static void`.)

def in_method
  f = Fiber.new { return 7 }
  begin
    f.resume
  rescue LocalJumpError => e
    p [e.message, e.exit_value]
  end
  "method kept running"
end

p in_method

# the same through an ensure, which still runs
def with_ensure
  f = Fiber.new do
    begin
      return 8
    ensure
      puts "ensure ran"
    end
  end
  begin
    f.resume
  rescue LocalJumpError => e
    p e.exit_value
  end
  "after"
end

p with_ensure

# a bare `return` carries nil
f = Fiber.new { return }
begin
  f.resume
rescue LocalJumpError => e
  p e.exit_value
end

# rescued INSIDE the fiber: the raise happens at the return, so the body's own
# handler sees it and the fiber's value is the handler's
g = Fiber.new do
  begin
    return 42
  rescue LocalJumpError => e
    e.exit_value
  end
end
p g.resume

# a Thread body is the same shape. The report_on_exception line a thread
# prints for an uncaught exception is formatted differently here than in
# CRuby, which is a separate difference; silence it so this test pins the
# LocalJumpError and not that.
Thread.report_on_exception = false

def in_thread
  t = Thread.new { return 5 }
  begin
    t.join
  rescue LocalJumpError => e
    p ["thread", e.exit_value]
  end
  "after"
end

p in_thread

# what must NOT change: a lambda inside a fiber returns from itself, `next`
# is the block's value, and a return in an ordinary block still returns from
# the enclosing method
h = Fiber.new do
  l = lambda { return 3 }
  l.call
end
p h.resume

p Fiber.new { next 5 }.resume

def plain_block
  [1, 2].each { |x| return x * 10 }
  "not reached"
end

p plain_block

# `break` is the same boundary: written in a fiber/thread body it has no
# enclosing block wrapper to deliver to, and CRuby answers it with
# LocalJumpError "break from proc-closure". Spinel emitted a bare C `break;`
# with no loop around it, which did not compile at all.

b = Fiber.new { break 6 }
begin
  b.resume
rescue LocalJumpError => e
  p [e.message, e.exit_value]
end

# through an ensure, which still runs
c = Fiber.new do
  begin
    break 7
  ensure
    puts "break ensure ran"
  end
end
begin
  c.resume
rescue LocalJumpError => e
  p e.exit_value
end

def break_in_thread
  t = Thread.new { break 8 }
  begin
    t.value
  rescue LocalJumpError => e
    p ["thread break", e.exit_value]
  end
  "after"
end

p break_in_thread

# and what must NOT change: a break in a block nested inside the fiber breaks
# that block, and one in a lambda returns from the lambda
d = Fiber.new { [1, 2, 3].each { |x| break x * 100 } }
p d.resume

e2 = Fiber.new do
  l = lambda { break 4 }
  l.call
end
p e2.resume

def ordinary_break
  r = [1, 2].each { |x| break x * 7 }
  p r
  "after"
end

p ordinary_break
