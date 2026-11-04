# Queue#pop(true) on an ivar-typed Queue, exercising the codegen's TY_QUEUE
# arm with argc == 1 (sp_Queue_pop_nb). The class shape mirrors dvtm's
# LLMWorker#_drain_pending_logs, which loops popping with no_wait and
# rescues ThreadError to break. CRuby and Spinel AOT both print "ok" --
# the upstream fix (#4211) keeps the ivar's Queue typing and the new
# no_wait arm handles the call.

class Drainer
  def initialize
    @q = Queue.new
  end

  def put(v)
    @q.push(v)
  end

  def drain
    out = []
    loop do
      begin
        out << @q.pop(true)
      rescue ThreadError
        break
      end
    end
    out
  end
end

d = Drainer.new
d.put("a")
d.put("b")
d.put("c")
got = d.drain
print got == ["a", "b", "c"] ? "ok" : "FAIL"
print "\n"

e = Drainer.new
print e.drain == [] ? "ok" : "FAIL"
print "\n"
