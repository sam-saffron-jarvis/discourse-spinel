# A hook runs after the program's own frames are gone, so a non-local jump out
# of one has nowhere to land: CRuby unwinds everything before it calls the end
# procs, and each of these misses and raises instead of jumping into a frame
# that has returned. The drain empties the proc-return, break and catch stacks
# before every hook for the same reason -- including between hooks, so a proc
# that escaped a method an EARLIER hook raised out of misses too.
$escaped = nil
def home
  $escaped = proc { return :late }
  raise "unwound past home"
end

at_exit do
  begin
    puts "escaped proc -> #{$escaped.call.inspect}"
  rescue LocalJumpError => e
    puts "escaped proc: LocalJumpError: #{e.message}"
  end
end
at_exit do
  begin
    throw :gone
  rescue UncaughtThrowError => e
    puts "throw: #{e.class}"
  end
end
at_exit { home }
catch(:gone) { puts "body" }
