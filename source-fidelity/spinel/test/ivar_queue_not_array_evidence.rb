# A Queue in an ivar with pushes of array literals: `push` is not array-fill
# evidence for a slot whose own write is a Queue.new -- the widening pass
# seeded the still-UNKNOWN slot as an array before the write merged, the
# merge unified Queue with it to the scalar poly box, and @q.pop fell to the
# generic dispatch's NoMethodError (#4211). The slot stays TY_QUEUE now and
# dispatches to the sp_Queue_* runtime.
def local_queue
  q = Queue.new
  q.push("a")
  q.pop
end

print "ok: local\n" if local_queue == "a"

class Message
  def initialize(content)
    @content = content
  end

  def role = "user"
  def content = @content
end

class IvarQueue
  def initialize
    @q = Queue.new
  end

  def take
    @q.pop
  end

  def submit(msg)
    if msg.is_a?(Message)
      if msg.role == "steer"
        @q.push(["steer", msg.content || ""])
        return
      end
      @q.push(["user", msg.content || ""])
      return
    end
    @q.push(["user", msg])
  end
end

q2 = IvarQueue.new
q2.submit(Message.new("b"))
print "ok: ivar\n" if q2.take == ["user", "b"]
q2.submit("raw")
p q2.take
