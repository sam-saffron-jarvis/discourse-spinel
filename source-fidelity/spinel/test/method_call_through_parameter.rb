# Method#call on a Method that arrived through a PARAMETER (so the target is
# not statically known) read the C return through the sp_int cast whatever
# the target answers: a String came back as its pointer, a poly as garbage
# (#4445). campfire's WebPush::Notification takes an `endpoint_ip_resolver:
# method(:resolved_endpoint_ip)` and pinned `4432406297` as the address. The
# bind site stamps the return kind; the call now reads it, the way the
# poly-slot call does, and the value is the boxed answer.
class Sub
  def name = "n"
  def pair = [1, 2]
  def num(x) = x + 1
  def flag = true
  def any(x) = x.odd? ? "odd" : x
end
m = Sub.new.method(:name)
puts m.call.inspect
def call_it(resolver)
  puts resolver.call.inspect
end
def call_1(r, v) = r.call(v).inspect
call_it(Sub.new.method(:name))
call_it(Sub.new.method(:pair))
call_it(Sub.new.method(:flag))
puts call_1(Sub.new.method(:num), 4)
puts call_1(Sub.new.method(:any), 3)
puts call_1(Sub.new.method(:any), 4)
def top_one = "top"
call_it(method(:top_one))
def wrong(r)
  r.call(1, 2)
  puts "no raise"
rescue ArgumentError, NoMethodError
  puts "raised"
end
wrong(Sub.new.method(:name))
