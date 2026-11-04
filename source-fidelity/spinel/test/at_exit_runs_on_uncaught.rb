# An uncaught exception runs the at_exit hooks before its error text is
# printed, which is the order CRuby prints them in. The hooks write to stderr
# as well as stdout so that the sidecar pins that order inside ONE stream: the
# harness compares stdout and stderr separately, and a build that printed the
# error first would still match a stdout-only expectation. The sidecar holds
# Spinel's tail format for an uncaught raise (an ordinary build has no frame
# symbols to prefix it with -- see test/uncaught_exception_message.rb).
at_exit { puts "hook 1 out"; STDERR.puts "hook 1 err (registered first, runs last)" }
at_exit { puts "hook 2 out"; STDERR.puts "hook 2 err (registered last, runs first)" }
puts "body"
raise ArgumentError, "boom"
