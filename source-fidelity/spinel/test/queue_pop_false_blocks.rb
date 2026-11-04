# Queue#pop(non_block): only a TRUTHY argument is no_wait. `pop(false)` and
# `pop(nil)` keep blocking, exactly like the bare pop -- a consumer written
# pop(false) waits for its producer, and raising ThreadError there would
# break the pairing (#4214 follow-up). A literal picks the helper at compile
# time; a runtime value decides by its own truthiness.
q = Queue.new
t = Thread.new { sleep 0.05; q.push(:late) }
p q.pop(false)
t.join
q2 = Queue.new
q2.push(1)
flag = [false, "x"][0]
tw = Thread.new { sleep 0.05; q2.push(:late2) }
p q2.pop(flag)
p q2.pop(flag)
tw.join
q3 = Queue.new
begin
  q3.pop(true)
rescue ThreadError => e
  puts "ThreadError"
end
sf = [true, "y"][0]
begin
  q3.pop(sf)
rescue ThreadError
  puts "ThreadError runtime"
end
