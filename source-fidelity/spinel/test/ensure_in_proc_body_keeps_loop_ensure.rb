# A lambda, proc or fiber body with its own begin/ensure, written inside a
# loop's begin/ensure region, leaves that region as it found it: a later
# `break` or `next` in the loop still runs the loop's ensure. On 4ea42f77
# the `next` case fails the C build (`_nxtf` undeclared), so this whole
# program does.
def with_break
  log = []
  i = 0
  while i < 3
    i += 1
    begin
      l = -> {
        begin
          log << [:lam, i]
        ensure
          log << [:lamens, i]
        end
      }
      l.call
      break if i == 2
    ensure
      i += 0
    end
  end
  log
end
p with_break
def with_next
  log = []
  i = 0
  while i < 3
    i += 1
    begin
      l = -> {
        begin
          log << [:lam, i]
        ensure
          log << [:lamens, i]
        end
      }
      l.call
      next if i == 2
    ensure
      i += 0
    end
  end
  log
end
p with_next
def with_fiber
  log = []
  i = 0
  while i < 3
    i += 1
    begin
      fb = Fiber.new { begin; log << i; ensure; log << -i; end }
      fb.resume
      break if i == 2
    ensure
      i += 0
    end
  end
  log
end
p with_fiber
