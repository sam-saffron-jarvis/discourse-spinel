# The arity guard on the receivers it did not reach: a builtin called with a
# count CRuby rejects raises CRuby's ArgumentError, message and all, on every
# handle kind the compiler types -- Regexp, MatchData, Proc, Method, Fiber,
# Thread, Queue and SizedQueue, ConditionVariable, IO, Dir, Exception,
# Enumerator, Random, a Struct or Data instance -- on a class or module
# constant (its own Class or Module surface, a Struct or Data class's
# readers, GC, Fiber, Thread), on a bare Kernel function, and on the
# universal names a builtin inherits from Object. Beside each, the in-range
# shape still answers, and a class's own row outranks Object's; a def of the
# name -- at top level, in a reopened Object, a module function, a class
# object's `class << self` accessor -- keeps its own dispatch, where an
# instance reader on a class does not reach the class object; a name handed
# to public_send reaches the raise; the receiver and the arguments are
# evaluated before the raise.
def bad
  yield
  puts "no error"
rescue ArgumentError => e
  puts "#{e.class}: #{e.message}"
end

re = /a(b)?/
bad { re.source(1) }
bad { re.match }
bad { re.match("ab", 0, 1) }
bad { re.names(nil) }
p re.source, re.match("xab", 1)[1], re.match?("a")

m = "xab".match(re)
bad { m.begin(0, 1) }
bad { m.length(1) }
bad { m.captures(1) }
bad { m.pre_match(1) }
bad { m[0, 1, 2] }
p m.begin(0), m[1], m.pre_match, m.captures

pr = proc { |x| x.to_s * 2 }
bad { pr.arity(1) }
bad { pr.lambda?(1) }
bad { pr.curry(1, 2) }
p pr.arity, pr.call(4), pr.lambda?

mt = 12.method(:to_s)
bad { mt.name(1) }
bad { mt.arity(nil) }
bad { mt.owner(1) }
p mt.name, mt.call, mt.arity

f = Fiber.new { 7 }
bad { f.alive?(nil) }
bad { Fiber.current(nil) }
p f.alive?, f.resume, f.alive?

t = Thread.new { 2 }
bad { t.join(1, 2) }
bad { t.value(1) }
bad { t.alive?(nil) }
bad { Thread.list(1) }
bad { Thread.current(1) }
bad { Thread.pass(1) }
p t.value, t.join.equal?(t), t.alive?

q = Queue.new
bad { q.size(1) }
bad { q.empty?(1) }
bad { q.pop(true, 1) }
bad { q.close(1) }
q.push(1)
q << 2
p q.size, q.pop, q.empty?
sq = SizedQueue.new(2)
sq.push(3)
bad { sq.size(1) }
p sq.size, sq.pop

cv = ConditionVariable.new
bad { cv.signal(1) }
bad { cv.broadcast(1) }
bad { cv.wait }
p cv.signal.equal?(cv)

bad { $stdout.fileno(1) }
bad { $stdout.tty?(1) }
bad { $stdin.closed?(nil) }
p $stdout.fileno, $stdout.closed?
File.open("/dev/null") do |fh|
  bad { fh.eof?(1) }
  bad { fh.closed?(1) }
  p fh.eof?, fh.read(0)
end

d = Dir.new(".")
bad { d.path(1) }
bad { d.close(1) }
p d.path
d.close

ex = RuntimeError.new("x")
bad { ex.message(1) }
bad { ex.full_message(1) }
bad { ex.backtrace(nil) }
p ex.message
begin
  raise "boom"
rescue => err
  bad { err.message(1) }
  bad { err.cause(1) }
  p err.message, err.cause
end

en = [1, 2].each
bad { en.next(1) }
bad { en.peek(nil) }
bad { en.size(1) }
bad { en.rewind(1) }
p en.next, en.peek, en.size

rn = Random.new(1)
bad { rn.seed(1) }
bad { rn.rand(1, 2) }
p rn.seed, rn.rand(1)

S = Struct.new(:a, :b)
s = S.new(1, 2)
bad { s.members(1) }
bad { s.to_a(1) }
bad { s.values(nil) }
bad { s.size(1) }
bad { S.members(nil) }
bad { S.keyword_init?(1) }
p s.members, s.to_a, S.members, s.a, s.size

D = Data.define(:x)
dd = D.new(x: 1)
bad { dd.members(1) }
bad { D.members(1) }
p dd.members, dd.x

class Foo
  def self.own(*a)
    a.size
  end
end
module Mod
end
bad { Foo.name(1) }
bad { Foo.superclass(1) }
bad { Foo.ancestors(nil) }
bad { Mod.name(1) }
p Foo.own(1, 2), Foo.name, Foo.superclass, Mod.name

bad { GC.start(1) }
bad { GC.count(1) }
GC.start
puts "gc ok"

# a refused call in argument or assignment position: the raise stands in
# for a value the analyzer has no type for
bad { p Fiber.current(nil).alive? }
bad { x = re.source(1); p x }
bad { p Thread.list(1).size }

bad { Integer() }
bad { Integer("1", 10, 3) }
bad { Float() }
bad { catch(:t) { throw :t, 1, 2 } }
bad { catch(1, 2) { } }
bad { catch(1, 2) }
bad { Rational(1, 2, 3) }
bad { block_given?(1) }
bad { caller(1, 2, 3) }
p Integer("7"), format("%02d", 3), catch(:t) { throw :t, 5 }, rand(1)

# a def of a Kernel function's name keeps its own dispatch, count and all
def srand(*a)
  "mine #{a.size}"
end
p srand(1, 2)

# the names every builtin inherits from Object
bad { 1.respond_to? }
bad { "s".is_a? }
bad { [1].instance_of?(Array, 1) }
bad { :s.nil?(1) }
bad { 1.5.frozen?(1) }
bad { (1..2).hash(1) }
bad { re.respond_to?(:match, true, 1) }
bad { q.instance_of?(Queue, 1) }
p 1.respond_to?(:to_s), "s".is_a?(String)
p [1].instance_of?(Array), re.respond_to?(:match)

# the receiver and the arguments are evaluated first, in order
def rx
  puts "recv"
  /a/
end
def ag
  puts "arg"
  1
end
bad { rx.source(ag) }

# a name handed to public_send, and Object's row beneath a class's own
nm = :frozen?
bad { 1.public_send(nm, nil) }
bad { 1.public_send(:frozen?, nil) }
p 1.public_send(:frozen?), 1.public_send(nm)
bad { 12.to_s(2, 3) }
bad { re.freeze(1) }
p 12.to_s(2), re.freeze.frozen?
bad { p rand(1, 2) }

# a class object's own accessors and a module's own functions keep their
# dispatch; an instance reader on a class does not reach the class object
class Request
  class << self
    attr_accessor :method
  end
end
Request.method = "POST"
p Request.method
class Bar
  attr_reader :name
end
bad { Bar.name(1) }
p Bar.name
module MF
  def freeze(a)
    "mf #{a}"
  end
  module_function :freeze
end
p MF.freeze(1)

# a reopened Object owns the name on an Integer and a String
class Object
  def itself(a)
    "obj #{a}"
  end
end
p 5.itself(1), "s".itself(2)
