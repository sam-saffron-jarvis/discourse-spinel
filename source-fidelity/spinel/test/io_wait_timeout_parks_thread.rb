# A timed readiness wait parks the green thread, not its OS worker.
#
# 300 threads wait, with a 3s timeout, on one pipe nobody has written to
# yet -- half through IO#wait_readable, half through a one-io IO.select.
# The main thread sleeps briefly and then writes a byte. When the wait
# parks the green thread, every waiter wakes readable within milliseconds
# of the write. When it blocks the OS worker in select(2) instead, every
# worker is pinned by a waiter, the main thread cannot run to write the
# byte, and each worker serves its waiters one full timeout at a time:
# nobody sees the byte, and the run takes minutes.
r, w = IO.pipe
n = 300
seen = Queue.new
arrived = Queue.new
threads = Array.new(n) do |i|
  Thread.new do
    arrived << 1
    ready = i.even? ? r.wait_readable(3) : IO.select([r], nil, nil, 3)
    seen << (ready.nil? ? 0 : 1)
  end
end
# Write only once every waiter has announced itself, so no thread can
# start late and find the pipe already readable. A waiter announces just
# before it parks, so give the last of them the tick it needs to get there.
n.times { arrived.pop }
sleep 0.05
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
w.write "x"
threads.each(&:join)
total = 0
n.times { total += seen.pop }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
puts "#{total} of #{n} readable"
puts(elapsed < 1.0 ? "woke promptly" : "woke late")

# The deadline still fires when nothing arrives, and a zero timeout is a
# peek that answers at once.
r2, _w2 = IO.pipe
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
p r2.wait_readable(0.2)
p IO.select([r2], nil, nil, 0.2)
p r2.wait_readable(0)
dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1
puts(dt >= 0.4 && dt < 1.5 ? "deadline honored" : "deadline off: #{dt}")
