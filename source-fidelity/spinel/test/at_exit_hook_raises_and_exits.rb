# Each at_exit hook runs under its own protect frame, the way CRuby runs each
# end proc: a hook that raises, and a hook that calls exit, end only themselves
# and the hooks registered before them still run. A hook's own error is printed
# where it happens -- between the hooks around it -- and the program's error is
# printed once, after all of them.
# The harness does not check the exit status (it would be 1, from the raising
# hook, which outranks the exiting hook's 5); what this pins is the stderr
# order, and that every hook ran.
at_exit { STDERR.puts "hook 1 (registered first, runs last)" }
at_exit { raise "hook 2 blew up" }
at_exit { STDERR.puts "hook 3 exiting"; exit 5 }
at_exit { STDERR.puts "hook 4 (registered last, runs first)" }
puts "body"
raise ArgumentError, "boom"
