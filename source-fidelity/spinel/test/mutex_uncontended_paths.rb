# The uncontended lock and unlock take no global lock now, so the paths that
# reach the waiter list have to keep agreeing with them: a contended acquire,
# a hand-off through unlock, try_lock against a held and a free mutex, a
# Monitor's reentrancy, and a condvar's release-and-reacquire.
require "monitor"

m = Mutex.new
p m.locked?
m.lock
p m.locked?
p m.owned?
p m.try_lock
m.unlock
p m.locked?
p m.try_lock
p m.locked?
m.unlock

begin
  m.unlock
rescue ThreadError => e
  puts "unlock: #{e.message}"
end

m.lock
begin
  m.lock
rescue ThreadError => e
  puts "relock: #{e.message}"
end
m.unlock

mon = Monitor.new
mon.synchronize do
  mon.synchronize do
    puts "monitor depth ok"
  end
end

shared = Mutex.new
counter = 0
ths = []
i = 0
while i < 8
  ths.push(Thread.new do
    own = Mutex.new
    k = 0
    while k < 2000
      own.lock
      own.unlock
      shared.synchronize { counter += 1 }
      k += 1
    end
  end)
  i += 1
end
ths.each { |t| t.join }
p counter
p shared.locked?

m2 = Mutex.new
cv = ConditionVariable.new
ready = false
w = Thread.new do
  m2.synchronize do
    while !ready
      cv.wait(m2)
    end
    "woken"
  end
end
sleep 0.05
m2.synchronize do
  ready = true
  cv.signal
end
p w.value
p m2.locked?
