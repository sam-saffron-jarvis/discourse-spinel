# Mutex#synchronize on a receiver the static type cannot see (a Mutex read
# out of an Array), with and without a user class that defines synchronize
# itself. The poly form used to run the block with no lock at all.
LOCKS = []
COUNTS = []
i = 0
while i < 2
  LOCKS.push(Mutex.new)
  COUNTS.push({ "n" => 0 })
  i += 1
end

def bump(s)
  h = COUNTS[s]
  LOCKS[s].synchronize do
    v = h["n"]
    Thread.pass if v % 97 == 0
    h["n"] = v + 1
  end
end

ts = []
4.times do
  ts << Thread.new do
    2000.times { bump(0) }
  end
end
ts.each(&:join)
p COUNTS[0]["n"]

# the block's value comes back through the poly receiver
r = LOCKS[1].synchronize { 40 + 2 }
p r

# an exception in the block releases the lock and propagates
begin
  LOCKS[0].synchronize { raise ArgumentError, "inside" }
rescue ArgumentError => e
  puts "rescued #{e.message}"
end
LOCKS[0].synchronize { puts "relocked" }

# a value that is not a Mutex raises what CRuby raises
begin
  LOCKS[5].synchronize { puts "never" }
rescue NoMethodError => e
  puts e.message
end

# a user class with its own synchronize shares the call site with a Mutex
class Guard
  def initialize; @n = 0; end
  def synchronize
    @n += 1
    r = yield
    puts "guard #{@n}"
    r
  end
end
MIXED = []
MIXED.push(Guard.new)
MIXED.push(Mutex.new)
def through(i)
  MIXED[i].synchronize { i * 10 }
end
p through(0)
p through(1)
begin
  through(1)
  MIXED[1].synchronize { raise "again" }
rescue => e
  puts "rescued #{e.message}"
end
p through(1)
