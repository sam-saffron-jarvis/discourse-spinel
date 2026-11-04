# Two threads must never be inside one Mutex#synchronize at once.
#
# An unlocker that finds a waiter counted AFTER it has already released takes
# the scheduler lock and hands the mutex to that waiter. The lock's own fast
# path takes a free mutex WITHOUT the scheduler lock, so a third thread could
# claim it in between, and writing the waiter's name over that owner left two
# threads inside the section at once.
#
# Both symptoms are pinned, because which one shows depends on the timing. A
# short count means two threads read and wrote it in the same window. An
# exception means the thread that unlocks second found a mutex it really did
# hold owned by someone else, and Thread#join re-raises it here, so the run
# ends before "ok". The allocation outside the section and the work inside it
# are what make the window wide enough to land on; a section too small to park
# anyone never reaches the hand-off path at all.
#
# It is a race, so it is not a certain detector: the defect it guards showed in
# 9 of 30 runs at eight workers before the fix, and in 0 of 40 after. What is
# deterministic is the answer when the mutex is correct, which is what the
# expected output holds.
COUNT = [0]
BUF = []
LOCK = Mutex.new
N = 12
R = 600
KEEP = 2000
P = 200
def page(t, i)
  b = String.new
  j = 0
  while j < P
    b << "t#{t}-#{i}-#{j}-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    j += 1
  end
  b
end
ths = []
N.times do |t|
  ths << Thread.new do
    i = 0
    while i < R
      p = page(t, i)
      LOCK.synchronize do
        COUNT[0] = COUNT[0] + 1
        BUF << p
        BUF.shift while BUF.size > KEEP
      end
      i += 1
    end
  end
end
ths.each { |th| th.join }
puts "count #{COUNT[0]} of #{N * R}"
puts "buf #{BUF.size}"
puts "ok"
