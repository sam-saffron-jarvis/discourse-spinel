# Kernel#abort from inside a rescue arm still runs the at_exit hooks: the
# message goes to stderr first (test/at_exit_runs_on_abort.rb.err.expected),
# then the hooks run, most recently registered first.
at_exit { puts "hook 1 (registered first, runs last)" }
at_exit { puts "hook 2 (registered last, runs first)" }
puts "body"
begin
  raise "unwound"
rescue
  abort "bye now"
end
