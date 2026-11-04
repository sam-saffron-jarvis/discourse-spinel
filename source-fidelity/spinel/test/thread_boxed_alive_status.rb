# Thread#alive? and Thread#status reached through an Array element (a boxed
# receiver): a pool polls `@workers.all? { |w| !w.alive? }` (#4463). And
# Thread#join through an element when a user class also defines `join`,
# which took the Thread arm out of the dispatch (#4466).
class Path
  def initialize(parts); @parts = parts; end
  def join; @parts.join("/"); end
end
puts Path.new(["a", "b"]).join

class Workers
  def initialize; @workers = []; end
  def start(n); n.times { @workers << Thread.new { sleep 0.01 } }; end
  def busy?; @workers.any? { |w| w.alive? }; end
  def done?; @workers.all? { |w| !w.alive? }; end
  def statuses; @workers.map { |w| w.status }; end
  def join_all; @workers.each { |w| w.join }; end
end
w = Workers.new
w.start(3)
p w.busy?
w.join_all
p w.busy?
p w.done?
p w.statuses

ts = 3.times.map { |i| Thread.new { sleep 0.001; i } }
ts.each { |t| t.join }
puts "joined #{ts.length}"
p ts.map { |t| t.alive? }
p ts.map { |t| t.status }

# a Fiber through the same element shape answers its own alive?
f = Fiber.new { Fiber.yield 1; 2 }
fs = [f]
p fs[0].alive?
f.resume; f.resume
p fs[0].alive?

# a value of another kind has no such method
begin
  [1][0].alive?
rescue NoMethodError => e
  puts e.class
end
