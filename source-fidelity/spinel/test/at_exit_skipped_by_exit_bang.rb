# exit! skips the at_exit hooks, as it does in CRuby -- the one termination
# where they must NOT run. The message goes to stderr because exit! skips the
# buffered-stdout flush too, so anything printed with puts first would be
# dropped by CRuby and kept by Spinel.
at_exit { puts "hook must not run" }
STDERR.puts "before exit!"
exit! 0
