# Thread#join(limit) answers nil when the limit ran out and the thread itself
# when it finished. The runtime had that right; the TYPED path printed the nil
# as a Thread, because a NULL sp_thread * inspected as
# `#<Thread:0x0000000000000000 dead>` -- so the one thing the return value
# exists to tell you read as the opposite of what it said, and "dead" named a
# thread that was still running (#4394, rofl0r).
t = Thread.new { sleep 5; :finished }
sleep 0.1

# (`p` on a Thread-typed local is not supported, so the interpolated form)
res = t.join(0.3)
puts res.inspect
p t.status
p t.alive?

# and the completing case still answers the thread
done = Thread.new { :quick }
p done.join(10).class
p done.value

# nil is nil however it is asked
p res.nil?
puts res.inspect
puts "ok"
