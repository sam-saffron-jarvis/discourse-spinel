# The at_exit hook table is a GC root. The registering expression stores the
# Proc in the table and drops it, so between `at_exit { }` and the hook
# running the table is the only reference to the Proc and to what it
# captured. Before the table was marked, this program segfaulted under
# SPINEL_GC_STRESS=1 -- on the one path that did run the hooks at all.
tag = ("captured " * 3).strip
at_exit { puts "hook sees: #{tag}" }
at_exit { puts "hook ran" }

a = []
200.times { |i| a << "x" * (i + 10) }
puts a.length
