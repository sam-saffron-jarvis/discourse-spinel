# Three paths where top-level self, the main object, was still missed (#5061):
# self.class inside a top-level instance_eval block answered Object for the
# receiver; a receiverless top-level instance_eval was refused; and
# self.m on a top-level def raised NoMethodError.
class Foo; end
f = Foo.new
p f.instance_eval { self.class }
p f.instance_exec { self.class }
p f.instance_eval { self.is_a?(Foo) }
g = f.instance_eval { self }
p g.class
p self.class
def k = self.class
p k
p 3.instance_eval { self.class }
instance_eval do
  puts "hi"
  puts self
end
r = instance_exec(3) { |x| x * 2 }
p r
def m = 42
def twice(x) = x * 2
def label=(v)
  $label = v
end
p m
p self.m
p self.twice(21)
self.label = "set"
p $label
p [1, 2].map { |x| self.twice(x) }
class Box
  def m = 7
  def call_m = self.m
end
p Box.new.call_m
