# A user-owned slice method opens polymorphic dispatch. Its builtin arm must
# retain String's Regexp/capture overload, not coerce both args to Integer.
class OtherSliceOwner
  def slice(first, second)
    [first, second]
  end
end

def boxed(value)
  [value, 17][0]
end

pattern = Regexp.union(/\A(?<host>\d+\.\d+\.\d+\.\d+)(?::\d+)?\z/, /\A(?<host>[a-f0-9:]+)\z/)
s = boxed("127.0.0.1:3000")
p s.slice(pattern, "host")
p s.slice(pattern, :host)
p s.slice(/(127)(\.0)/, 2)
p s.slice(/(127)(\.0)/, -1)
p s.slice(/(127)(\.0)/, -3)
p boxed("abcdefghijkl").slice(/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)/, 12)
p s.slice(/never/, "missing")
p s.slice(0, 3)
p boxed([1, 2, 3]).slice(1, 2)
p boxed({a: 1, b: 2, c: 3}).slice(:a, :c)
p boxed(OtherSliceOwner.new).slice("first", "second")
begin
  s.slice(/(?<present>127)/, "missing")
rescue IndexError => error
  puts error.class
end
begin
  boxed(nil).slice(pattern, "host")
rescue NoMethodError => error
  puts error.name
end

# Held arguments run once, left-to-right, before the builtin dispatch.
class SliceArgumentOrder
  def initialize
    @events = []
  end
  def receiver
    @events << "receiver"
    boxed("abc")
  end
  def pattern
    @events << "pattern"
    /(?<part>b)/
  end
  def capture
    @events << "capture"
    "part"
  end
  def run
    p receiver.slice(pattern, capture)
    p @events
  end
end
SliceArgumentOrder.new.run
