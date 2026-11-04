# The value form of `loop do` (`r = loop do ... end`) is a C loop wherever
# it appears, so its `break` and `next` leave the loop and not the enclosing
# proc, fiber or lambda. On 4ea42f77 each case fails when run alone:
# the proc answers nil, the fiber raises LocalJumpError, and
# the lambda segfaults (this whole program then prints nothing).
pr = proc { i = 0; r = loop do i += 1; next if i == 1; break i if i == 3; end; [r, :after_p] }
p pr.call
begin
  f = Fiber.new { r = loop do break :fb end; Fiber.yield r; :fdone }
  p [f.resume, f.resume]
rescue LocalJumpError => e
  p e.class
end
l = -> { i = 0; r = loop do i += 1; break i * 5 if i == 2; end; [r, :after_l] }
p l.call
