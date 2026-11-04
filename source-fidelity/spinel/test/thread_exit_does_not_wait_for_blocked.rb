# main() finishing is the end of the program: CRuby kills the other threads
# where they stand. The exit drain waited for anything outstanding, and a
# thread merely BLOCKED counted -- so `Thread.new { sleep 30 }` at the top of
# a script hung the process after its last statement, and adding `exit 0` was
# the difference between a program that ended and one that did not
# (#4394, #4397, rofl0r).
#
# What the drain still does, and CRuby does not, is give a RUNNABLE
# fire-and-forget thread its turn first. That is deliberate and unchanged; it
# is why the side effect below is printed here.
sleeper = Thread.new { sleep 300; puts "must not print" }

r, w = IO.pipe
blocked_on_io = Thread.new { r.read; puts "must not print" }

# an explicit join still waits for the thread it names
joined = Thread.new { sleep 0.05; :done }
p joined.join(5).class

sleep 0.1
puts "main done"

# created last so its turn can only come from the exit drain: ordering the
# program this way is what makes the output deterministic, since a thread
# started earlier may print before or after the join returns.
Thread.new { puts "fire and forget ran" }
