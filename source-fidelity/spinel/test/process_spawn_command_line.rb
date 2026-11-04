# Process.spawn with ONE string and no arguments is a command line, as for
# Kernel#system: a shell character hands it to the shell, and plain words are
# split. It was exec'd as a program name, so `spawn("sleep 0")` was ENOENT.
# The parent's buffered output is flushed before the fork, so its lines and
# the child's come out in program order.
r, w = IO.pipe
pid = Process.spawn("echo one two | tr a-z A-Z", out: w)
w.close
Process.waitpid2(pid)
p r.read
pid = Process.spawn("sleep 0")
p Process.waitpid2(pid)[1].success?
print "before "
pid = Process.spawn("echo after", out: $stdout)
Process.waitpid2(pid)
pid = Process.spawn("/bin/echo", "still argv", out: $stdout)
p Process.waitpid2(pid)[1].success?
begin
  Process.spawn("no_such_program_xyz_0")
rescue SystemCallError => e
  p e.class
end
