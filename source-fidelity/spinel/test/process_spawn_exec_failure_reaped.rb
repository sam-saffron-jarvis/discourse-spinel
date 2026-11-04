# A spawn whose exec fails raises, and leaves no child behind.
#
# The child forks, finds nothing to exec, reports its errno through the pipe
# and exits 127. The parent raises Errno::ENOENT for it, and reaps the child
# before it raises, so a later Process.waitpid2(-1) finds no child at all
# instead of answering with the dead child's exit 127. That is what CRuby
# does; before this change every line below that expects ECHILD printed
# "child 127" instead, and each failed spawn left a zombie until the program
# exited.

def failed_spawn
  begin
    Process.spawn("/this-command-does-not-exist-spinel")
    "spawned"
  rescue Errno::ENOENT
    "ENOENT"
  end
end

def failed_spawn_with_input
  begin
    Process.spawn("/this-command-does-not-exist-spinel", in: "/dev/null")
    "spawned"
  rescue Errno::ENOENT
    "ENOENT"
  end
end

def wait_any
  begin
    pid, status = Process.waitpid2(-1)
    "child #{status.exitstatus}"
  rescue Errno::ECHILD
    "ECHILD"
  end
end

# One failure leaves nothing to wait for
p failed_spawn
p wait_any

# Three failures in a row leave nothing to wait for either
3.times { failed_spawn }
p wait_any

# A failed spawn that also opened a redirection is reaped the same way
p failed_spawn_with_input
p wait_any

# A failure does not disturb a child that was started before it
pid = Process.spawn("/usr/bin/true")
p failed_spawn
p Process.waitpid2(pid)[0] == pid
p wait_any
