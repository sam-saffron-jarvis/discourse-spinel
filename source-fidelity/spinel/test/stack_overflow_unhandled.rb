# A stack overflow nothing rescues is reported, not a silent death. Before the
# fault handler knew the thread's own guard, the process took the default
# SIGSEGV disposition: no message, exit 139, and whatever the program had
# already printed still sitting in stdout's buffer.
#
# The sidecar holds Spinel's tail format for an uncaught raise, the same shape
# test/at_exit_runs_on_uncaught.rb pins; CRuby prefixes its own frame to the
# identical text and exits 1 as well. The at_exit hooks do NOT run here, and
# that is deliberate: they are Ruby code, and the stack they would run on is
# the one that just ran out.
puts "before"
def deep(n) = n < 0 ? 0 : 1 + deep(n + 1)
deep(0)
puts "unreachable"
