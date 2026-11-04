# at_exit hooks run when the program ends by Kernel#exit, not only when main
# falls off its end -- here the exit happens inside a rescue arm, where no
# handler is left in scope and the runtime terminates the process directly.
# A hook that calls exit itself runs the hooks still pending exactly once and
# its own status becomes the program's (0 here, so the suite sees a clean run).
at_exit { puts "hook 1 (registered first, runs last)" }
at_exit { puts "hook 2 runs and then exits"; exit }
at_exit { puts "hook 3 (registered last, runs first)" }

begin
  raise "unwound"
rescue => e
  puts "rescued #{e.message}"
  exit true
end
puts "not reached"
