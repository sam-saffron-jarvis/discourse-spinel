# Thread#join with a timeout: returns self if the thread finishes in time,
# nil if the timeout expires. The timeout form returns sp_RbVal (not
# sp_thread*), so we use separate local variables for each result.

# Thread that finishes quickly: join should return the thread.
t1 = Thread.new { sleep 0.05; "done" }
r1 = t1.join(1.0)
puts r1 == t1

# Thread that takes too long: join should return nil. The thread is
# killed before sched_drain, otherwise main would block for the full
# 10s sleep waiting for the helper worker to exit.
t2 = Thread.new { sleep 10; "never" }
r2 = t2.join(0.1)
puts r2.nil?
t2.kill rescue nil

# Thread that finishes within the timeout: returns the thread.
t3 = Thread.new { sleep 0.1; "done" }
r3 = t3.join(1.0)
puts r3 == t3

# Bare join (no timeout) still works.
t4 = Thread.new { "immediate" }
t4.join
puts true
