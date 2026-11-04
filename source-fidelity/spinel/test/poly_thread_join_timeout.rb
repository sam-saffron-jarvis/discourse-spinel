# `join` on a receiver that only reads poly -- a thread held in an array -- is
# claimed by one arm that means Array#join. With no argument, or a String one,
# the runtime helper does test the receiver's kind and joins the thread, so the
# wait is right and only the discarded result differs. With a NUMERIC argument
# there is no such reading: Array#join(5) is a TypeError in CRuby, so it can
# only be Thread#join(limit), and it must answer the thread or nil rather than
# a joined string.

ts = 3.times.map { |i| Thread.new { sleep 0.05 } }
p ts.map { |t| t.join(5).nil? }

# it answers when the thread finishes, not when the limit does
t0 = Time.now
quick = [Thread.new { sleep 0.05 }]
r = quick[0].join(5)
puts r.nil?
puts((Time.now - t0) < 1.0)

# and nil when the thread outlives the limit
slow = [Thread.new { sleep 5 }]
puts slow[0].join(0.2).nil?

# Array#join is untouched: no argument, a String separator, and the nested
# array read out of a mixed container that makes the receiver poly
p ["a", "b"].join("-")
mixed = [["a", "b"], 1]
p mixed[0].join
p mixed[0].join("-")

# a numeric separator on something that is not a Thread still raises the
# separator slot's own TypeError, naming the class as written
begin
  mixed[0].join(5)
rescue TypeError => e
  p e.message
end
begin
  mixed[0].join(5.5)
rescue TypeError => e
  p e.message
end
