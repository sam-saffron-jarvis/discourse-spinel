# Warning[] / Warning[]= / Warning.warn, and Kernel#warn's category: gate
# reading the same runtime flags (stderr asserted via the .err.expected
# sidecar).
def try(label)
  r = yield
  puts "#{label}: => #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
try("defaults") { [Warning[:deprecated], Warning[:experimental], Warning[:performance]] }
try("strict") { Warning[:strict_unused_block] }
try("set") { Warning[:experimental] = false }
try("read back") { Warning[:experimental] }
try("truthy") { r = (Warning[:experimental] = "yes"); [r, Warning[:experimental]] }
try("bogus get") { Warning[:bogus] }
try("bogus set") { Warning[:bogus] = true }
try("warn ret") { Warning.warn("warned line\n") }
try("kernel warn") { warn("plain msg") }
try("dep off") { warn("dep hidden", category: :deprecated) }
try("dep on") { Warning[:deprecated] = true; warn("dep shown", category: :deprecated); Warning[:deprecated] = false }
try("exp off") { Warning[:experimental] = false; warn("exp hidden", category: :experimental) }
try("perf") { warn("perf hidden", category: :performance) }
try("warn bogus cat") { warn("never", category: :bogus) }
STDERR.flush
