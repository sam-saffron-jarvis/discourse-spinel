# Collection methods on a receiver that is nil at run time raise NoMethodError,
# as in CRuby. Every one of these used to answer as though nil were an empty
# collection (nil, false, true, 0, "", []), or absorb the write (#4485).
def check(label)
  puts "#{label.ljust(16)} #{yield}"
rescue NoMethodError => e
  puts "#{label.ljust(16)} #{e.class}"
end

begin
  nil.first
rescue NoMethodError => e
  puts e.message
end

x = nil
check("x[0]")          { x[0].inspect }
check('x["k"]')        { x["k"].inspect }
check('x.dig("k")')    { x.dig("k").inspect }
check("x.at(0)")       { x.at(0).inspect }
check("x.values_at")   { x.values_at(0).inspect }
check("x.first")       { x.first.inspect }
check("x.last")        { x.last.inspect }
check("x.key?")        { x.key?("k").inspect }
check("x.include?")    { x.include?("k").inspect }
check("x.member?")     { x.member?("k").inspect }
check("x.empty?")      { x.empty?.inspect }
check("x.any?")        { x.any?.inspect }
check("x.all?")        { x.all?.inspect }
check("x.none?")       { x.none?.inspect }
check("x.one?")        { x.one?.inspect }
check("x.count")       { x.count.inspect }
check("x.join")        { x.join(",").inspect }
check("x.map")         { x.map { |e| e }.inspect }
check("x.sum")         { x.sum.inspect }
check('x["k"] = 1')    { x["k"] = 1; "absorbed" }
check("x.push(1)")     { x.push(1).inspect }
check("x.clear")       { x.clear.inspect }
check("x.each_pair")   { x.each_pair { |k, v| k }.inspect }
check("x.each_key")    { x.each_key { |k| k }.inspect }
check("x.each_value")  { x.each_value { |v| v }.inspect }

# a receiver that is a collection only sometimes: the same names, the same raise
y = ARGV.empty? ? nil : {"k" => 1}
check("y[0]")          { y[0].inspect }
check("y.first")       { y.first.inspect }
check("y.empty?")      { y.empty?.inspect }
check("y.map")         { y.map { |e| e }.inspect }
check("y.push(1)")     { y.push(1).inspect }
check('y["k"] = 1')    { y["k"] = 1; "absorbed" }
k = ARGV.empty? ? "k" : 0
check("y[k]")          { y[k].inspect }

# the real collections keep answering
z = ARGV.empty? ? [1, 2] : nil
check("z.first")       { z.first.inspect }
check("z.push(3)")     { z.push(3).inspect }
check("z.any?")        { z.any?.inspect }
h = ARGV.empty? ? {"k" => 1} : nil
check("h.each_pair")   { h.each_pair { |k, v| k }.inspect }
check("h.key?")        { h.key?("k").inspect }
q = Queue.new
w = ARGV.empty? ? q : nil
w.push(1)
check("queue size")    { q.size }
