# Process.waitpid2 sets $? to the status it reaped.
#
# Kernel#system and backticks already write $?; a spawn followed by
# waitpid2 left it at whatever the last system call or backtick stored,
# so a program that checks $? after reaping its own child read a stale
# value. On master every waitpid2 line below prints the value the system
# call before it left behind.

system("sh", "-c", "exit 9")
p $?.to_i >> 8

pid = Process.spawn("false")
Process.waitpid2(pid)
p $?.to_i >> 8

pid = Process.spawn("true")
Process.waitpid2(pid)
p $?.to_i >> 8

pid = Process.spawn("sh", "-c", "exit 7")
Process.waitpid2(pid)
p $?.to_i >> 8

# the wait-any form reaps the same way
pid = Process.spawn("sh", "-c", "exit 3")
Process.waitpid2(-1)
p $?.to_i >> 8

# a child that died of a signal: the low seven bits carry the signal
pid = Process.spawn("sleep", "5")
Process.kill("TERM", pid)
Process.waitpid2(pid)
p $?.to_i & 0x7f

# a wait that finds no child leaves $? alone
begin
  Process.waitpid2(-1)
rescue Errno::ECHILD
  p $?.to_i & 0x7f
end

# system after a spawn still writes its own status
system("sh", "-c", "exit 2")
p $?.to_i >> 8
