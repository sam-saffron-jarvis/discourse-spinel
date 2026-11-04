# Thread.report_on_exception / Thread#report_on_exception: the flags, and
# which terminations they report.
#
# The report line itself goes to stderr and its text differs from CRuby's
# (spinel names the thread by a small serial and prints one line where CRuby
# prints the thread's inspect plus the raising frame), so this pins WHEN the
# report happens rather than what it says: each case below turns the flag on
# or off and reports the effect through stdout.

p Thread.report_on_exception
t = Thread.new { 1 }
p t.report_on_exception
t.join

# both setters answer the value they were given
p(Thread.report_on_exception = false)
p Thread.report_on_exception
p(Thread.report_on_exception = true)

u = Thread.new { sleep 0 }
p(u.report_on_exception = false)
p u.report_on_exception
u.join

# the instance flag overrides the class flag in both directions
Thread.report_on_exception = false
v = Thread.new { sleep 0 }
p v.report_on_exception
v.join
Thread.report_on_exception = true

# a SystemExit is not a thread dying badly: CRuby reports every other class
# and stays silent for this one, then lets it surface at join with its status
Thread.report_on_exception = true
def exiting
  t = Thread.new { exit 7 }
  begin
    t.join
  rescue SystemExit => e
    p ["surfaced at join", e.status]
  end
  "after"
end
p exiting

# Thread#kill is not an exception, so nothing is reported and join is quiet
k = Thread.new { sleep 5 }
k.kill
k.join
p "killed cleanly"

# an ordinary exception still reaches the joiner whatever the flag says
Thread.report_on_exception = false
w = Thread.new { raise ArgumentError, "bad" }
begin
  w.join
rescue ArgumentError => e
  p ["joined", e.message]
end
