# A spawn that fails names what failed, and leaves its exit status in $?.
#
# The child reports its errno through the pipe, and now also whether it was
# the chdir or the exec that failed. The parent raises the matching Errno
# with CRuby's message, the strerror text followed by the program or the
# directory, where before it read "cannot execute - No such file or
# directory" and named nothing. The child it reaps before raising was the
# last one waited for, so $? reads its exit 127 afterwards, as it does under
# CRuby; before this change $? was left as it was.

def try
  yield
  "no raise"
rescue SystemCallError => e
  "#{e.class}: #{e.message}"
end

# $? starts from a child that exited 0
system("true")
p $?.to_i >> 8

# A program that does not exist is named, and $? reads its exit 127
p try { Process.spawn("/this-command-does-not-exist-spinel") }
p $?.to_i >> 8

# With arguments the program is still what is named
p try { Process.spawn("/this-command-does-not-exist-spinel", "one", "two") }

# A file that cannot be executed is named with its own errno
p try { Process.spawn("/etc/passwd") }

# A chdir: that fails names the directory, not the program
system("true")
p try { Process.spawn("true", chdir: "/no-such-directory-spinel") }
p $?.to_i >> 8

# A spawn that succeeds after a failure is unaffected
pid = Process.spawn("true")
p Process.waitpid2(pid)[0] == pid
