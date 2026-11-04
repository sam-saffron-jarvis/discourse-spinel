# Thread-local storage must survive a garbage collection. Set a key,
# allocate enough to collect several times while writing another key
# repeatedly, then read the first key back.
class Holder
  attr_accessor :name
  def initialize(name)
    @name = name
  end
end
def churn(label)
  Thread.current[:keep] = Holder.new(label)
  junk = []
  i = 0
  while i < 400_000
    junk << ("y" * 64) + i.to_s
    junk = [] if junk.length > 2000
    Thread.current[:counter] = i
    i += 1
  end
  kept = Thread.current[:keep]
  puts "#{label}: #{kept.nil? ? 'LOST' : kept.name} counter=#{Thread.current[:counter]}"
end
churn("main")
t = Thread.new { churn("worker") }
t.join
puts "done"
