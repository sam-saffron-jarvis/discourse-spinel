# Queue#pop(true) on a local Queue, dispatched through the codegen's TY_QUEUE
# arm (argc == 1 now reaches sp_Queue_pop_nb, the no_wait variant). Empty
# queue must raise ThreadError -- the caller pattern of `begin; pop(true);
# rescue ThreadError; break; end` drains a worker queue without blocking.
# CRuby and Spinel AOT both print "ok" with the same line set.

q = Queue.new
got = nil
begin
  got = q.pop(true)
rescue ThreadError
  got = :thread_error
end
print got == :thread_error ? "ok" : "FAIL"
print "\n"

q.push("x")
print q.pop(true) == "x" ? "ok" : "FAIL"
print "\n"

q.push("a")
q.push("b")
print q.pop(true) == "a" ? "ok" : "FAIL"
print "\n"
print q.pop(true) == "b" ? "ok" : "FAIL"
print "\n"
begin
  q.pop(true)
  print "FAIL\n"
rescue ThreadError
  print "ok\n"
end
