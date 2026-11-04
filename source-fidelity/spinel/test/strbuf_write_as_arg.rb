# A write to a mutable-string local used as a call argument,
# `show(buf = +"abc")`. The parameter is typed from the write (the local's
# sp_String *) while the write's value form is the const char * copy, so
# the C did not compile. The argument is now the local's handle: the
# parameter and the local are one object, as in Ruby.

# 1. the reported shape
def show(s) = s.length
buf = nil
n = show(buf = +"abc")
3.times { buf << "d" }
p [n, buf]

# 2. the callee mutates its parameter: the caller's local sees it
def bang(s)
  s << "!"
  s.length
end
t = nil
m = bang(t = +"hi")
2.times { t << "?" }
p [m, t]

# 3. two arguments with side effects, evaluated left to right
def pair(a, b) = "#{a}/#{b}"
x = nil
y = nil
r = pair(x = +"l", y = +"r")
x << "1"
y << "2"
p [r, x, y]

# 4. a method on an object
class Box
  def put(s)
    s << "#"
    s.length
  end
end
u = nil
k = Box.new.put(u = +"box")
u << "~"
p [k, u]
