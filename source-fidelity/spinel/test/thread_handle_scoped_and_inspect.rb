# `Thread::Mutex` is CRuby's own name for the Mutex class, and holding one in a
# variable did not compile:
#
#     x = Thread::Mutex.new    ->  assigning to 'sp_RbVal' from 'sp_mutex *'
#
# The bare-constant branch of the inference types `Mutex.new` as a Mutex; the
# CONSTANT PATH branch had Mutex in a list that answers "carry it boxed", so
# the local was declared sp_RbVal while the emitter still wrote sp_Mutex_new().
# Inference and emission disagreed, and C said so. Thread::Queue,
# Thread::SizedQueue and Thread::ConditionVariable were never in that list and
# had always worked through the path spelling, which is what made this one look
# arbitrary rather than missing (#4421).
#
# The second half is what the reporter's `p x` found. These handles had no
# inspect arm at all, so `p mutex` refused to compile -- and `mutex.inspect`
# fell to the nil-degrade placeholder and answered "[]", which is a silent
# wrong answer rather than a gap. They render as Object's default does, which
# is what CRuby prints for them.
#
# The addresses are sliced off below: they are a real difference between any
# two runs, CRuby's included, and what is being pinned is the shape and the
# class name.
def shape(s)
  s.split(":0x").first.to_s
end

# holding one, through both spellings
scoped = Thread::Mutex.new
bare = Mutex.new
scoped.lock
scoped.unlock
bare.synchronize { puts "bare synchronized" }
scoped.synchronize { puts "scoped synchronized" }

# the class is named the same either way
puts scoped.class
puts bare.class

# inspect, to_s and p all render the handle
puts shape(scoped.inspect)
puts shape(scoped.to_s)
puts shape(bare.inspect)

q = Thread::Queue.new
q.push(7)
puts q.pop
puts q.class
puts shape(q.inspect)

cv = Thread::ConditionVariable.new
puts cv.class
puts shape(cv.inspect)
