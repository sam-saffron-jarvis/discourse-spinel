# A hook that a non-main thread registers WHILE the hooks are already running
# still runs. On the exit paths the drain runs on the main thread with the
# program's other threads alive -- CRuby keeps them alive across the hooks
# too -- so a thread can call at_exit in the middle of it, and in the threaded
# build that is a push onto the table from one OS thread while main pops from
# it. The two queues make the interleaving deterministic: the thread registers
# only once the first hook has started, and that hook finishes only once the
# registration is in.
started = Queue.new
registered = Queue.new
Thread.new do
  started.pop
  at_exit { puts "hook registered from the thread during the drain" }
  registered.push(true)
end
at_exit do
  started.push(true)
  registered.pop
  puts "main hook"
end
exit
