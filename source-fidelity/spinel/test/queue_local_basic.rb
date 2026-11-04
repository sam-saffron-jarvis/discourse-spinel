# Queue.push / #pop / #empty? on a local Queue dispatched through the
# codegen's TY_QUEUE arm. Mirrors the worker/main thread handshake
# patterns used by every spin program that uses Thread::Queue as a
# mailbox. CRuby and Spinel AOT both print "ok" because the static
# receiver type is provably TY_QUEUE here (a local initialized with
# Queue.new) and the codegen dispatches to sp_Queue_push / sp_Queue_pop
# without falling through to the generic call handler.

q = Queue.new
q.push(["user", "hello"])
q.push(["steer", "nudge"])
items = []
items << q.pop
items << q.pop
print items[0].inspect, "\n"
print items[1].inspect, "\n"
print q.size, "\n"
print q.empty? ? "true" : "false"
print "\n"
