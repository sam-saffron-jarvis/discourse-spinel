# Top-level self is main, an Object whose to_s and inspect are "main" (#4926)
p self
x = self
p x
p self.to_s
p self.inspect
p self.nil?
p self.frozen?
p self.is_a?(Object)
p self == self
p [self].size
3.times { p self }
def m; self; end
p m.class
pr = -> { self }
p pr.call.class
p pr.call
puts "#{self}"
p self.equal?(m)
# main survives collections: it is held by the runtime, not by a local
a = []
200000.times { |i| a << "s#{i}" }
a = nil
GC.start
p self
p [self, 1].inspect
