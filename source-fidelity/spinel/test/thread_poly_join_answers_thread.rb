# `join` on a boxed receiver in a program that spawns threads: a Thread
# answers itself (Thread#join), an Array its joined String. The call used to
# be typed String, so a joined thread came back as "" and `.value` on it had
# nothing to ask.
class Worker
  def join
    "joined"
  end
end
q = [Thread.new { 42 }, Worker.new]
q.each do |x|
  r = x.join
  p r.class
end
t = Thread.new { 7 }
u = [t][0]
p u.join.class
p u.join.value
xs = [[1, 2], Thread.new { 3 }]
xs.each do |x|
  r = x.join
  p r.value if r.is_a?(Thread)
  p r.length if r.is_a?(String)
end
h = { "t" => Thread.new { 9 } }
p h["t"].join.value
b = [["a", "b"]][0]
p b.join("-")
