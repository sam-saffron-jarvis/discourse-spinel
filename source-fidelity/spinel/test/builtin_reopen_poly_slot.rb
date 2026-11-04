# A method added to a builtin by a class reopen must stay reachable through a
# poly slot: the reopen class is never `.new`ed, so the instantiated census
# dropped its arm, and the plain cls_id key could not map a scalar's tag to it
# anyway (#4219).
class String
  def shout
    self + "!"
  end

  def repeat(n)
    self * n
  end
end

class Integer
  def double_up
    self * 2
  end
end

def pick(flag)
  flag ? "hi" : 7
end

v = pick(true)
puts v.shout
puts v.repeat(3)

w = pick(false)
puts w.double_up

# a user class owning the same name keeps its own arm beside the builtin's
class Megaphone
  def shout
    "MEGA"
  end
end

def pick3(n)
  n == 0 ? "lo" : (n == 1 ? Megaphone.new : 5)
end

puts pick3(0).shout
puts pick3(1).shout

# narrowing still takes the static path
x = pick(true)
if x.is_a?(String)
  puts x.shout
end
